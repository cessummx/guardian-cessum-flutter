import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'helpers.dart';
import 'foto_web_picker.dart';
import 'teacher_profile.dart';
import 'auth/session_store.dart';

/// Catálogo de motivos. El comprobante es OBLIGATORIO en los que traen
/// documento de respaldo por norma; en los demás es opcional.
const List<List<String>> _kMotivos = [
  // [motivo, '1' si exige comprobante, ayuda]
  ['Incapacidad médica', '1', 'Adjunta la incapacidad expedida por el IMSS/ISSSTE o el certificado médico.'],
  ['Comisión oficial', '1', 'Adjunta el oficio de comisión o la constancia del evento.'],
  ['Enfermedad sin incapacidad', '0', 'Si tienes receta o constancia médica, adjúntala.'],
  ['Duelo familiar', '0', 'Puedes adjuntar el acta o el documento que lo acredite.'],
  ['Caso fortuito o fuerza mayor', '0', 'Corte de energía, clima, accidente, falla de transporte.'],
  ['Asunto personal', '0', 'Describe brevemente la causa.'],
  ['Otro', '0', 'Explícalo en la descripción.'],
];

const List<String> _kDias = [
  'Lunes',
  'Martes',
  'Miércoles',
  'Jueves',
  'Viernes',
  'Sábado',
  'Domingo'
];

/// NORMA DE REPOSICIÓN Y GRABACIÓN. Si cambia el acuerdo institucional se
/// editan estas tres constantes y nada más.
// La reposición es INMEDIATA: antes de la clase, o a más tardar este número
// de días naturales DESPUÉS de la fecha de la sesión.
const int _kDiasMaxReposicion = 3;
const int _kHorasGrabacion = 48; // plazo para subir la grabación a Moodle
const int _kDiasAnticipacion = 0; // 0 = puede avisar el mismo día

/// El DOCENTE avisa por adelantado que no podrá impartir una sesión: motivo, descripción,
/// comprobante y si la va a reponer. No confundir con "Faltas de mis alumnos".
class JustificarInasistenciaScreen extends StatefulWidget {
  const JustificarInasistenciaScreen({super.key});

  @override
  State<JustificarInasistenciaScreen> createState() =>
      _JustificarInasistenciaScreenState();
}

class _JustificarInasistenciaScreenState
    extends State<JustificarInasistenciaScreen> {
  bool _cargando = true;
  String? _error;
  String _correo = '';
  String _docente = '';

  List<Map<String, dynamic>> _clases = [];
  List<Map<String, dynamic>> _historial = [];

  // Clase elegida y captura
  Map<String, dynamic>? _clase;
  final _fechaCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _fechaRepoCtrl = TextEditingController();
  String? _motivo;
  bool _repondra = true;
  DocElegido? _comprobante;
  bool _acuerdo = false;
  bool _enviando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _fechaCtrl.dispose();
    _descCtrl.dispose();
    _fechaRepoCtrl.dispose();
    super.dispose();
  }

  bool get _exigeComprobante {
    if (_motivo == null) return false;
    for (final m in _kMotivos) {
      if (m[0] == _motivo) return m[1] == '1';
    }
    return false;
  }

  String get _ayudaMotivo {
    if (_motivo == null) return '';
    for (final m in _kMotivos) {
      if (m[0] == _motivo) return m[2];
    }
    return '';
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      _correo = await SessionStore.validEmail() ?? '';
      final perfil = await TeacherProfile.load();
      _docente = perfil?.nombreCompleto ?? '';

      final uriC = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'mis_grupos',
        'correo': _correo,
      });
      final respC = await http.get(uriC).timeout(const Duration(seconds: 30));
      final dataC = jsonDecode(respC.body) as Map<String, dynamic>;
      if (dataC['ok'] != true) throw Exception(dataC['error'] ?? 'Error');
      _clases = ((dataC['grupos'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      await _cargarHistorial();
    } catch (e) {
      _error = 'No se pudieron cargar tus clases. Revisa tu conexión.';
    }
    if (mounted) setState(() => _cargando = false);
  }

  Future<void> _cargarHistorial() async {
    if (_docente.isEmpty) return;
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'inasistencias_docentes_listar',
        'docente': _docente,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] == true) {
        _historial = ((data['inasistencias'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
    } catch (_) {}
  }

  /// PRÓXIMAS 4 fechas en que toca esa clase. El aviso es previo, así que no
  /// tiene sentido ofrecer fechas que ya pasaron.
  List<String> _fechasProximas(String dia) {
    final idx = _kDias.indexOf(dia.trim());
    if (idx < 0) return [];
    final objetivo = idx + 1; // DateTime.monday == 1
    final out = <String>[];
    for (int i = 0; i <= 42 && out.length < 4; i++) {
      final d = _hoy.add(Duration(days: i));
      if (d.weekday == objetivo) out.add(_fmt(d));
    }
    return out;
  }

  DateTime get _hoy {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  DateTime? _parse(String txt) {
    final m = RegExp(r'^(\d{1,2})[/-](\d{1,2})[/-](\d{4})$').firstMatch(txt.trim());
    if (m == null) return null;
    try {
      return DateTime(int.parse(m.group(3)!), int.parse(m.group(2)!),
          int.parse(m.group(1)!));
    } catch (_) {
      return null;
    }
  }

  /// Ventana permitida para reponer: desde hoy y hasta la sesión + el plazo.
  String get _ventanaRepo {
    final f = _parse(_fechaCtrl.text);
    if (f == null) {
      return 'Repónla antes de la clase o a más tardar $_kDiasMaxReposicion '
          'días naturales después.';
    }
    return 'Repónla antes de la clase o a más tardar el '
        '${_fmt(f.add(const Duration(days: _kDiasMaxReposicion)))}.';
  }

  /// Fecha tope para subir la grabación: reposición + _kHorasGrabacion.
  String get _limiteGrabacion {
    final r = _parse(_fechaRepoCtrl.text);
    if (r == null) return '';
    return _fmt(r.add(const Duration(hours: _kHorasGrabacion)));
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _adjuntar() async {
    final doc = await seleccionarDocumento();
    if (doc == null) return;
    setState(() => _comprobante = doc);
  }

  String? _validar() {
    if (_clase == null) return 'Elige la clase.';
    final f = _parse(_fechaCtrl.text);
    if (f == null) return 'Escribe la fecha de la sesión como dd/mm/aaaa.';
    if (f.isBefore(_hoy)) {
      return 'Esta pantalla es para avisar por adelantado; esa fecha ya pasó. '
          'Si la sesión ya se perdió, repórtala con la coordinación.';
    }
    if (_kDiasAnticipacion > 0 &&
        f.difference(_hoy).inDays < _kDiasAnticipacion) {
      return 'Avisa con al menos $_kDiasAnticipacion día(s) de anticipación.';
    }
    if (_motivo == null) return 'Selecciona el motivo.';
    if (_exigeComprobante && _comprobante == null) {
      return 'El motivo "$_motivo" requiere que adjuntes el comprobante.';
    }
    if (_repondra) {
      final r = _parse(_fechaRepoCtrl.text);
      if (r == null) return 'Escribe la fecha de reposición como dd/mm/aaaa.';
      if (r.isBefore(_hoy)) return 'La fecha de reposición ya pasó.';
      if (r.difference(f).inDays > _kDiasMaxReposicion) {
        final tope = _fmt(f.add(const Duration(days: _kDiasMaxReposicion)));
        return 'La reposición debe ser antes de la clase o a más tardar el '
            '$tope ($_kDiasMaxReposicion días naturales después).';
      }
    }
    if (!_acuerdo) {
      return 'Falta que aceptes el acuerdo de reposición y grabación.';
    }
    return null;
  }

  Future<void> _enviar() async {
    final falla = _validar();
    if (falla != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(falla)));
      return;
    }
    final c = _clase!;
    setState(() => _enviando = true);
    try {
      final Map<String, dynamic> payload = {
        'accion': 'inasistencia_docente_enviar',
        'docente': _docente,
        'correoDocente': _correo,
        'programa': (c['programa'] ?? '').toString(),
        'generacion': (c['generacion'] ?? '').toString(),
        'grupo': (c['grupo'] ?? '').toString(),
        'materia': (c['materia'] ?? '').toString(),
        'hora': (c['hora'] ?? '').toString(),
        'fechaSesion': _fechaCtrl.text.trim(),
        'motivo': _motivo,
        'descripcion': _descCtrl.text.trim(),
        'repondra': _repondra ? 'SI' : 'NO',
        'fechaReposicion': _repondra ? _fechaRepoCtrl.text.trim() : '',
        'acuerdo': _acuerdo ? 'SI' : 'NO',
        'compromisoGrabacion': _repondra ? _limiteGrabacion : '',
      };
      if (_comprobante != null) {
        payload['base64'] = base64Encode(_comprobante!.bytes);
        payload['mime'] = _comprobante!.mime;
        payload['nombreArchivo'] = _comprobante!.nombre;
      }
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode(payload))
          .timeout(const Duration(seconds: 180));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        backgroundColor: Colors.green,
        content: Text(
            'Aviso enviado. Coordinación lo revisará y te informará el resultado.'),
      ));
      setState(() {
        _enviando = false;
        _clase = null;
        _motivo = null;
        _comprobante = null;
        _acuerdo = false;
        _repondra = true;
        _fechaCtrl.clear();
        _descCtrl.clear();
        _fechaRepoCtrl.clear();
      });
      await _cargarHistorial();
      if (mounted) setState(() {});
    } catch (e) {
      if (!mounted) return;
      setState(() => _enviando = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('No se pudo enviar: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Justificar mi inasistencia'),
        actions: [
          IconButton(
              onPressed: _cargando ? null : _cargar,
              icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                )
              : _cuerpo(),
    );
  }

  Widget _cuerpo() {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cessumGold.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Text(
            'Aquí avisas POR ADELANTADO que no vas a poder impartir una '
            'sesión. Vicerrectoría la autoriza y se le avisa al grupo. Con '
            'este mismo aviso queda registrada tu reposición y tu compromiso '
            'de subir la grabación.',
            style: TextStyle(fontSize: 12.5, height: 1.4),
          ),
        ),
        const SizedBox(height: 14),
        if (_clase == null) ..._selectorClase() else ..._formulario(),
        const SizedBox(height: 18),
        if (_historial.isNotEmpty) ..._listaHistorial(),
        const SizedBox(height: 30),
      ],
    );
  }

  List<Widget> _selectorClase() {
    if (_clases.isEmpty) {
      return [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: Text('No tienes clases activas asignadas.',
              textAlign: TextAlign.center),
        ),
      ];
    }
    return [
      const Text('¿En cuál clase no vas a poder dar?',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
      const SizedBox(height: 6),
      ..._clases.map((c) => Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.menu_book, color: cessumRed),
              title: Text((c['materia'] ?? '').toString(),
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w600)),
              subtitle: Text(
                '${c['programa']} · ${c['generacion']} · Grupo ${c['grupo']}'
                '${(c['dia'] ?? '').toString().isNotEmpty ? ' · ${c['dia']}' : ''}'
                '${(c['hora'] ?? '').toString().isNotEmpty ? ' ${c['hora']}' : ''}',
                style: const TextStyle(fontSize: 11.5),
              ),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: () => setState(() => _clase = c),
            ),
          )),
    ];
  }

  List<Widget> _formulario() {
    final c = _clase!;
    final sugeridas = _fechasProximas((c['dia'] ?? '').toString());
    return [
      Card(
        child: ListTile(
          dense: true,
          leading: const Icon(Icons.menu_book, color: cessumRed),
          title: Text((c['materia'] ?? '').toString(),
              style:
                  const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
          subtitle: Text(
            '${c['programa']} · ${c['generacion']} · Grupo ${c['grupo']}',
            style: const TextStyle(fontSize: 11.5),
          ),
          trailing: TextButton(
            onPressed: _enviando ? null : () => setState(() => _clase = null),
            child: const Text('Cambiar', style: TextStyle(color: cessumRed)),
          ),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _fechaCtrl,
        enabled: !_enviando,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(
          labelText: 'Fecha de la sesión que NO vas a impartir *',
          hintText: 'dd/mm/aaaa',
          border: OutlineInputBorder(),
          isDense: true,
        ),
      ),
      if (sugeridas.isNotEmpty) ...[
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          children: sugeridas
              .map((f) => ActionChip(
                    label: Text(f, style: const TextStyle(fontSize: 11.5)),
                    onPressed: _enviando
                        ? null
                        : () => setState(() => _fechaCtrl.text = f),
                  ))
              .toList(),
        ),
        Text('Tus próximas sesiones de ${c['dia']}.',
            style: TextStyle(fontSize: 11, color: cessumFaint(context))),
      ],
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        value: _motivo,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Motivo de la inasistencia *',
          border: OutlineInputBorder(),
          isDense: true,
        ),
        items: _kMotivos
            .map((m) => DropdownMenuItem(
                  value: m[0],
                  child: Text(m[0], style: const TextStyle(fontSize: 13)),
                ))
            .toList(),
        onChanged: _enviando ? null : (v) => setState(() => _motivo = v),
      ),
      if (_ayudaMotivo.isNotEmpty) ...[
        const SizedBox(height: 4),
        Text(_ayudaMotivo,
            style: TextStyle(fontSize: 11, color: cessumMuted(context))),
      ],
      const SizedBox(height: 12),
      TextField(
        controller: _descCtrl,
        enabled: !_enviando,
        maxLines: 3,
        decoration: const InputDecoration(
          labelText: 'Descripción breve',
          border: OutlineInputBorder(),
          isDense: true,
        ),
      ),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 10),
        decoration: BoxDecoration(
          color: (_exigeComprobante && _comprobante == null)
              ? cessumRed.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(
                _comprobante != null
                    ? Icons.check_circle
                    : Icons.description_outlined,
                size: 20,
                color: _comprobante != null
                    ? const Color(0xFF1E8E3E)
                    : (_exigeComprobante ? cessumRed : cessumFaint(context))),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _comprobante != null
                    ? 'Adjunto: ${_comprobante!.nombre}'
                    : (_exigeComprobante
                        ? 'Comprobante OBLIGATORIO para este motivo'
                        : 'Comprobante (opcional)'),
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: _exigeComprobante && _comprobante == null
                        ? FontWeight.w700
                        : FontWeight.normal),
              ),
            ),
            TextButton(
              onPressed: _enviando ? null : _adjuntar,
              child: Text(_comprobante != null ? 'Cambiar' : 'Adjuntar',
                  style: const TextStyle(color: cessumRed, fontSize: 12)),
            ),
          ],
        ),
      ),
      const SizedBox(height: 6),
      SwitchListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        value: _repondra,
        activeColor: cessumGold,
        onChanged: _enviando ? null : (v) => setState(() => _repondra = v),
        title: const Text('Voy a reponer esta sesión',
            style: TextStyle(fontSize: 13)),
        subtitle: const Text(
          'Si la activas, la reposición queda registrada con este mismo aviso.',
          style: TextStyle(fontSize: 11),
        ),
      ),
      if (_repondra) ...[
        TextField(
          controller: _fechaRepoCtrl,
          enabled: !_enviando,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Fecha en que la repondrás *',
            hintText: 'dd/mm/aaaa',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 4),
        Text(_ventanaRepo,
            style: TextStyle(fontSize: 11, color: cessumMuted(context))),
      ] else
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: cessumRed.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text(
            'Toda sesión no impartida debe reponerse. Si no la repones, '
            'coordinación tendrá que resolver el caso contigo.',
            style: TextStyle(fontSize: 11.5, height: 1.35),
          ),
        ),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        decoration: BoxDecoration(
          color: _acuerdo
              ? const Color(0xFF1E8E3E).withValues(alpha: 0.08)
              : cessumGold.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _acuerdo
                ? const Color(0xFF1E8E3E).withValues(alpha: 0.35)
                : cessumGold.withValues(alpha: 0.45),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Acuerdo de reposición y grabación',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              '· Repongo la sesión ANTES de la clase o, a más tardar, '
              '$_kDiasMaxReposicion días naturales después de la fecha.\n'
              '· Subo la grabación al Aula Virtual dentro de las '
              '$_kHorasGrabacion horas posteriores a la reposición'
              '${_limiteGrabacion.isNotEmpty ? ", es decir a más tardar el $_limiteGrabacion" : ""}.\n'
              '· Aviso al grupo con anticipación.',
              style: const TextStyle(fontSize: 11.5, height: 1.45),
            ),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _acuerdo,
              activeColor: const Color(0xFF1E8E3E),
              onChanged: _enviando
                  ? null
                  : (v) => setState(() => _acuerdo = v ?? false),
              title: const Text('Acepto el acuerdo',
                  style: TextStyle(fontSize: 12.5)),
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: cessumRed,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onPressed: _enviando ? null : _enviar,
          icon: _enviando
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.send, size: 18),
          label: Text(_enviando ? 'Enviando...' : 'Enviar aviso'),
        ),
      ),
    ];
  }

  Color _colorEstatus(String e) {
    if (e == 'Justificada') return const Color(0xFF1E8E3E);
    if (e == 'No justificada') return cessumRed;
    return cessumGold;
  }

  List<Widget> _listaHistorial() {
    return [
      const Divider(),
      const SizedBox(height: 6),
      const Text('Mis avisos anteriores',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
      const SizedBox(height: 6),
      ..._historial.map((h) {
        final est = (h['estatus'] ?? '').toString();
        final col = _colorEstatus(est);
        final comp = (h['comprobante'] ?? '').toString();
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text((h['materia'] ?? '').toString(),
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: col.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(est,
                          style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: col)),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  'Sesión del ${h['fechaSesion']} · ${h['motivo']}'
                  '${(h['repondra'] ?? '') == 'SI' ? ' · Repone el ${h['fechaReposicion']}' : ' · Sin reposición'}',
                  style: const TextStyle(fontSize: 11.5, height: 1.35),
                ),
                if ((h['resolucion'] ?? '').toString().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Coordinación: ${h['resolucion']}',
                        style: TextStyle(fontSize: 11.5, color: col)),
                  ),
                if (comp.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => Helpers.abrirUrlExterna(comp, context),
                      icon: const Icon(Icons.attach_file,
                          size: 15, color: cessumRed),
                      label: const Text('Ver comprobante',
                          style: TextStyle(color: cessumRed, fontSize: 11.5)),
                    ),
                  ),
              ],
            ),
          ),
        );
      }),
    ];
  }
}

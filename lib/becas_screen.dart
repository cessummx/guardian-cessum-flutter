// becas_screen.dart
// (ago-7) BECAS DEL ALUMNO
// Apartado del Instituto de Becas y Crédito Educativo (IBCEES) y demás
// otorgantes: el alumno informa si cuenta con beca, su tipo y condición,
// sube su resolución (PDF o imagen) y da seguimiento al estatus de su
// registro (En revisión / Validada / Rechazada).

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'helpers.dart';
import 'foto_web_picker.dart';
import 'student_autolink.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

class BecasScreen extends StatefulWidget {
  const BecasScreen({super.key});

  @override
  State<BecasScreen> createState() => _BecasScreenState();
}

class _BecasScreenState extends State<BecasScreen> {
  bool _cargando = true;
  String? _error;
  String _matricula = '';
  List<Map<String, dynamic>> _becas = [];
  /// Beca del sistema financiero (hoja Becas) — la que YA aplica descuento a
  /// la colegiatura. Es distinta de _becas, que son las resoluciones que el
  /// alumno subió por esta pantalla. Sin esto, a quien ya tiene beca activa
  /// la pantalla le decía "aún no has registrado ninguna".
  Map<String, dynamic>? _vigente;

  // Formulario
  static const _tipos = [
    'Instituto de Becas y Crédito Educativo (IBCEES)',
    'Beca Telmex',
    'Beca CESSUM-IDENAP',
    'Beca institucional CESSUM',
    'Beca de empresa / patrocinador',
    'Otra',
  ];

  /// (ago-21) Las becas de convenio traen condiciones fijas, y decirlas en la
  /// pantalla evita la pregunta que llega después por WhatsApp: cuánto pago
  /// de inscripción y cuánto se me descuenta cada mes.
  static const _condicionesFijas = <String, String>{
    'Beca CESSUM-IDENAP':
        '30% de descuento en colegiaturas mensuales · Inscripción con '
            '\$250 de descuento: pagas \$200 en lugar de \$450.',
  };
  String _tipoSel = _tipos.first;
  final _otorganteCtrl = TextEditingController();
  final _condicionCtrl = TextEditingController();
  List<int>? _archivoBytes;
  String _archivoMime = '';
  bool _enviando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _otorganteCtrl.dispose();
    _condicionCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final perfil = await StudentAutoLink.sincronizarPerfilGuardado();
      _matricula = perfil?.matricula ?? '';
      if (_matricula.isEmpty) throw Exception('Sin matrícula.');
      final r = await http
          .get(Uri.parse(
              '$guardianUrl?accion=becas_alumno&matricula=${Uri.encodeComponent(_matricula)}'))
          .timeout(const Duration(seconds: 60));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true) throw Exception(d['error'] ?? 'Error');
      if (!mounted) return;
      setState(() {
        _becas = ((d['becas'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _vigente = d['vigente'] == null
            ? null
            : Map<String, dynamic>.from(d['vigente'] as Map);
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error =
            'No se pudo cargar la sección de becas. Revisa tu conexión e intenta de nuevo.';
      });
    }
  }

  Future<void> _elegirArchivo() async {
    final doc = await seleccionarDocumento(tipo: 'ambos');
    if (doc == null || !mounted) return;
    setState(() {
      _archivoBytes = doc.bytes;
      _archivoMime = doc.mime;
    });
  }

  Future<void> _enviar() async {
    final condicion = _condicionCtrl.text.trim();
    if (condicion.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Describe la condición de tu beca (porcentaje, promedio requerido, vigencia…).')));
      return;
    }
    setState(() => _enviando = true);
    try {
      final body = <String, dynamic>{
        'accion': 'beca_registrar',
        'matricula': _matricula,
        'tipoBeca': _tipoSel,
        'otorgante': _otorganteCtrl.text.trim(),
        'condicion': condicion,
      };
      if (_archivoBytes != null) {
        body['base64'] = base64Encode(_archivoBytes!);
        body['mime'] = _archivoMime;
      }
      final r = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode(body))
          .timeout(const Duration(seconds: 120));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true) throw Exception(d['error'] ?? 'Error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.green,
          content: Text('${d['mensaje'] ?? 'Beca registrada.'}')));
      setState(() {
        _archivoBytes = null;
        _archivoMime = '';
        _otorganteCtrl.clear();
        _condicionCtrl.clear();
      });
      _cargar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: cessumRed,
          content: Text('No se pudo registrar: $e')));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  /// Tarjeta de la beca que la institución ya tiene aplicada. Se muestra
  /// arriba de todo para que el alumno vea de inmediato que su descuento
  /// existe, aunque nunca haya subido nada por esta pantalla.
  Widget _tarjetaVigente() {
    final v = _vigente;
    if (v == null) return const SizedBox.shrink();
    final activa = v['activa'] == true;
    final porc = (v['porcentaje'] ?? 0).toString();
    final estatus = (v['estatus'] ?? '').toString();
    final ordinario = (v['montoOrdinario'] ?? 0);
    final conBeca = (v['montoBeca'] ?? 0);
    final folio = (v['folioConvenio'] ?? '').toString();
    final notas = (v['notas'] ?? '').toString();
    final color = activa ? const Color(0xFF1E7B34) : cessumGold;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(activa ? Icons.verified : Icons.hourglass_top,
                  size: 18, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                    activa
                        ? 'TIENES UNA BECA ACTIVA'
                        : 'TU BECA ESTÁ EN ESTATUS: ${estatus.toUpperCase()}',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                        color: color)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('$porc% de descuento en tu colegiatura',
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w900, color: color)),
          if (activa && _num(ordinario) > 0 && _num(conBeca) > 0) ...[
            const SizedBox(height: 4),
            Text(
                'Tu mensualidad pasa de \$${_money(ordinario)} a '
                '\$${_money(conBeca)} MXN.',
                style: const TextStyle(fontSize: 12.5, height: 1.35)),
          ],
          if (folio.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Convenio $folio',
                style: const TextStyle(fontSize: 11, color: Colors.black54)),
          ],
          if (notas.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(notas,
                style: const TextStyle(fontSize: 11.5, color: Colors.black54)),
          ],
          const SizedBox(height: 8),
          Text(
              activa
                  ? 'Ya está aplicada: lo verás reflejado en Pagos → Cuánto debo. '
                      'No necesitas volver a registrarla.'
                  : 'Mientras no esté activa, tu mensualidad se cobra completa. '
                      'Si crees que hay un error, acude a Vicerrectoría.',
              style: const TextStyle(fontSize: 11.5, height: 1.35)),
        ],
      ),
    );
  }

  double _num(dynamic v) =>
      v is num ? v.toDouble() : (double.tryParse('$v') ?? 0);

  String _money(dynamic v) {
    final n = _num(v).round().toString();
    final b = StringBuffer();
    for (var i = 0; i < n.length; i++) {
      if (i > 0 && (n.length - i) % 3 == 0) b.write(',');
      b.write(n[i]);
    }
    return b.toString();
  }

  /// Aviso con las condiciones de la beca elegida, cuando son de convenio.
  Widget _condicionDeLaBeca() {
    final texto = _condicionesFijas[_tipoSel];
    if (texto == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cessumGold.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cessumGold.withValues(alpha: 0.4)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.card_giftcard, size: 17, color: cessumGold),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('CONDICIONES DE ESTA BECA',
                  style: TextStyle(
                      fontSize: 9.5,
                      letterSpacing: .9,
                      fontWeight: FontWeight.w800,
                      color: cessumGold)),
              const SizedBox(height: 3),
              Text(texto,
                  style: const TextStyle(fontSize: 12.5, height: 1.5)),
            ],
          ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Becas',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
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
                        Text(_error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 13)),
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
    return RefreshIndicator(
      color: cessumRed,
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _tarjetaVigente(),
          // Apartado IBCEES
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cessumGold.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cessumGold.withValues(alpha: 0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('🏛️ INSTITUTO DE BECAS Y CRÉDITO EDUCATIVO',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                        color: Color(0xFF8A5A0F))),
                SizedBox(height: 6),
                Text(
                    '¿Obtuviste alguna beca? Sube tu resolución aquí. '
                    'Registrar tu beca ante la Vicerrectoría es indispensable '
                    'para que se aplique correctamente en tus pagos y quede '
                    'asentada en tu expediente.',
                    style: TextStyle(
                        fontSize: 12.5,
                        height: 1.45,
                        color: Color(0xFF6B4A0C))),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Formulario de registro
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE6E0D4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('REGISTRAR MI BECA',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                        color: cessumRed)),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _tipoSel,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: '¿Con qué tipo de beca cuentas?',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final t in _tipos)
                      DropdownMenuItem(
                          value: t,
                          child: Text(t,
                              style: const TextStyle(fontSize: 12.5))),
                  ],
                  onChanged: (v) =>
                      setState(() => _tipoSel = v ?? _tipos.first),
                ),
                _condicionDeLaBeca(),
                const SizedBox(height: 10),
                TextField(
                  controller: _otorganteCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Otorgante (si elegiste "Otra" o empresa)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _condicionCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Condición de la beca',
                    hintText:
                        'Ej. 50% de colegiatura, mantener promedio mínimo de 9.0, vigencia ago-2026 a jul-2027…',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                          foregroundColor: cessumGold),
                      onPressed: _enviando ? null : _elegirArchivo,
                      icon: const Icon(Icons.attach_file, size: 17),
                      label: Text(
                          _archivoBytes == null
                              ? 'Adjuntar mi resolución (PDF o foto)'
                              : '📎 Resolución adjunta ✓',
                          style: const TextStyle(fontSize: 12),
                          overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: cessumRed,
                        foregroundColor: Colors.white,
                        padding:
                            const EdgeInsets.symmetric(vertical: 12)),
                    onPressed: _enviando ? null : _enviar,
                    icon: _enviando
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.school, size: 18),
                    label: Text(
                        _enviando
                            ? 'Enviando…'
                            : 'Registrar mi beca',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Mis registros
          const Text('📋 MIS BECAS REGISTRADAS',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4)),
          const SizedBox(height: 8),
          if (_becas.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                  'Aún no has registrado ninguna beca. Si cuentas con una, '
                  'regístrala arriba para que quede en tu expediente.',
                  style: TextStyle(fontSize: 12.5, color: Colors.black54)),
            )
          else
            for (final b in _becas)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE6E0D4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                        child: Text('${b['tipoBeca'] ?? ''}',
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800)),
                      ),
                      _chipEstatus('${b['estatus'] ?? 'En revisión'}'),
                    ]),
                    if ('${b['otorgante'] ?? ''}'.isNotEmpty)
                      Text('Otorgante: ${b['otorgante']}',
                          style: const TextStyle(fontSize: 11.5)),
                    if ('${b['condicion'] ?? ''}'.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text('Condición: ${b['condicion']}',
                            style: const TextStyle(
                                fontSize: 11.5, height: 1.4)),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text('Registrada el ${b['fecha'] ?? ''}',
                          style: const TextStyle(
                              fontSize: 10.5, color: Colors.black54)),
                    ),
                    if ('${b['notas'] ?? ''}'.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text('Observaciones: ${b['notas']}',
                            style: const TextStyle(
                                fontSize: 11, color: cessumRed)),
                      ),
                    if ('${b['resolucionUrl'] ?? ''}'.isNotEmpty)
                      TextButton.icon(
                        style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            foregroundColor: cessumGold),
                        onPressed: () => Helpers.abrirUrlExterna(
                            '${b['resolucionUrl']}', context),
                        icon: const Icon(Icons.description, size: 15),
                        label: const Text('Ver mi resolución',
                            style: TextStyle(fontSize: 11.5)),
                      ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _chipEstatus(String e) {
    final el = e.toLowerCase();
    Color c;
    String txt;
    if (el.contains('valida')) {
      c = const Color(0xFF1E8E3E);
      txt = '✓ Validada';
    } else if (el.contains('rechaz')) {
      c = cessumRed;
      txt = 'Rechazada';
    } else {
      c = const Color(0xFF8A5A0F);
      txt = 'En revisión';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(txt,
          style: TextStyle(
              fontSize: 10.5, fontWeight: FontWeight.w800, color: c)),
    );
  }
}

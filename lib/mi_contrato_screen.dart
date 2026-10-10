// Pantalla "Mi contrato" para el profesor.
//
// Flujo: el profesor llena sus datos personales UNA vez (se guardan), elige el
// tipo de contrato, captura los datos del periodo, LEE el contrato dentro de la
// app y lo FIRMA digitalmente (reusa su firma ya registrada). Todo se genera
// desde el Guardián; no se sube ningún archivo a Drive.
//
// Acciones del Guardián:
//   GET  contrato_datos_get   -> datos personales guardados
//   POST contrato_datos_set   -> guarda datos personales (una vez)
//   POST contrato_preview     -> {ok, html}  (para leer, sin firmar)
//   POST contrato_firmar      -> {ok, pdfUrl, folio}  (PDF firmado)

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

class MiContratoScreen extends StatefulWidget {
  const MiContratoScreen({super.key});

  @override
  State<MiContratoScreen> createState() => _MiContratoScreenState();
}

class _MiContratoScreenState extends State<MiContratoScreen> {
  // Campos de la PERSONA (se guardan una sola vez).
  static const List<List<String>> _persona = [
    ['NOMBRE', 'Nombre completo'],
    ['RFC', 'RFC'],
    ['CURP', 'CURP'],
    ['ESTUDIOS', 'Estudios (ej. Maestría en Educación)'],
    ['TITULO', 'Título / certificado'],
    ['CEDULA', 'Cédula profesional'],
    ['EXPEDIDO_POR', 'Expedida por (institución)'],
    ['DOMICILIO', 'Domicilio'],
    ['CUENTA', 'Cuenta bancaria'],
    ['CLABE', 'CLABE interbancaria'],
    ['BANCO', 'Institución bancaria'],
    ['TITULAR', 'Titular de la cuenta'],
  ];

  // Vigencia (6 campos) y fecha de firma (3 campos) compartidos.
  static const List<List<String>> _vigencia = [
    ['VIG_DIA_INI', 'Inicio · día'],
    ['VIG_MES_INI', 'Inicio · mes'],
    ['VIG_ANIO_INI', 'Inicio · año'],
    ['VIG_DIA_FIN', 'Fin · día'],
    ['VIG_MES_FIN', 'Fin · mes'],
    ['VIG_ANIO_FIN', 'Fin · año'],
  ];
  static const List<List<String>> _firmaFecha = [
    ['FIRMA_DIA', 'Firma · día'],
    ['FIRMA_MES', 'Firma · mes'],
    ['FIRMA_ANIO', 'Firma · año'],
  ];
  static const List<List<String>> _pago = [
    ['MONTO', 'Monto (cifra)'],
    ['MONTO_LETRA', 'Monto (con letra)'],
    ['FORMA_PAGO', 'Forma de pago'],
    ['DIA_PAGO', 'Día de pago'],
    ['DIAS_AVISO', 'Días de aviso previo'],
  ];

  // Específicos de DOCENCIA / MIXTA.
  static const List<List<String>> _docencia = [
    ['PROGRAMA', 'Programa académico'],
    ['ASIGNATURA', 'Asignatura'],
    ['SISTEMA', 'Sistema (ej. No escolarizado)'],
    ['HORAS', 'Número de horas'],
    ['PERFIL', 'Perfil profesional'],
  ];
  // Vacaciones solo MIXTA (12 campos).
  static const List<List<String>> _vacaciones = [
    ['VAC1_DIA_INI', '1er periodo · día inicio'],
    ['VAC1_MES_INI', '1er periodo · mes inicio'],
    ['VAC1_DIA_FIN', '1er periodo · día fin'],
    ['VAC1_MES_FIN', '1er periodo · mes fin'],
    ['VAC2_DIA_INI', '2º periodo · día inicio'],
    ['VAC2_MES_INI', '2º periodo · mes inicio'],
    ['VAC2_DIA_FIN', '2º periodo · día fin'],
    ['VAC2_MES_FIN', '2º periodo · mes fin'],
    ['VAC3_DIA_INI', '3er periodo · día inicio'],
    ['VAC3_MES_INI', '3er periodo · mes inicio'],
    ['VAC3_DIA_FIN', '3er periodo · día fin'],
    ['VAC3_MES_FIN', '3er periodo · mes fin'],
  ];
  // Específicos de TRABAJADOR.
  static const List<List<String>> _trabajador = [
    ['SERVICIOS', 'Servicios contratados'],
    ['AREA', 'Área'],
    ['PERFIL', 'Perfil profesional'],
    ['PERIODO_INI', 'Periodo · inicio'],
    ['PERIODO_FIN', 'Periodo · fin'],
    ['MODALIDAD', 'Modalidad (presencial / remota / híbrida)'],
    ['ACTIVIDADES', 'Actividades'],
    ['OBLIGACIONES', 'Obligaciones'],
  ];

  // Campos largos que se muestran con varias líneas.
  static const Set<String> _multilinea = {
    'DOMICILIO',
    'PERFIL',
    'ACTIVIDADES',
    'OBLIGACIONES',
    'MONTO_LETRA',
    'SERVICIOS',
  };

  final Map<String, TextEditingController> _ctrl = {};

  // Tipos visibles -> configuración (tipo backend + semanas).
  static const List<Map<String, String>> _tipos = [
    {'label': 'Docencia · 4 semanas', 'tipo': 'docencia', 'num': '4', 'texto': 'cuatro'},
    {'label': 'Docencia · 5 semanas', 'tipo': 'docencia', 'num': '5', 'texto': 'cinco'},
    {'label': 'Docencia · 10 semanas', 'tipo': 'docencia', 'num': '10', 'texto': 'diez'},
    {'label': 'Docencia · Mixta', 'tipo': 'mixta', 'num': '10', 'texto': 'diez'},
    {'label': 'Trabajador (servicios)', 'tipo': 'trabajador', 'num': '', 'texto': ''},
  ];

  int _tipoIdx = 0;
  String _correo = '';
  Map<String, dynamic>? _estatus;
  bool _cargando = true;
  bool _guardando = false;
  bool _generando = false;
  String _folio = '';

  // Materias del profesor para autocompletar el periodo.
  List<Map<String, dynamic>> _materias = [];
  int? _materiaIdx;
  // Asignaturas que ya tienen contrato (normalizadas) -> estatus.
  final Map<String, String> _contratadas = {};

  // Nombre combinado del bloque ("A y B") o la materia sola.
  String _nombreContrato(Map<String, dynamic> m) {
    final noms = (m['bloqueNoms'] as List?)?.cast<String>() ?? const [];
    if (noms.length > 1) {
      return noms.length == 2
          ? '${noms[0]} y ${noms[1]}'
          : '${noms.sublist(0, noms.length - 1).join(', ')} y ${noms.last}';
    }
    return (m['materia'] ?? '').toString();
  }

  bool _esBloque(Map<String, dynamic> m) =>
      ((m['bloqueNoms'] as List?)?.length ?? 0) > 1;

  String _normMat(String s) => s.trim().toLowerCase();

  TextEditingController _c(String k) =>
      _ctrl.putIfAbsent(k, () => TextEditingController());

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  @override
  void dispose() {
    for (final c in _ctrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<Map<String, dynamic>> _post(Map<String, dynamic> body) async {
    final resp = await http
        .post(Uri.parse(guardianUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
            body: jsonEncode(body))
        .timeout(const Duration(seconds: 90));
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<void> _cargarDatos() async {
    try {
      _correo = (await SessionStore.validEmail()) ?? '';
      final uri = Uri.parse(
          '$guardianUrl?accion=contrato_datos_get&correo=${Uri.encodeComponent(_correo)}');
      final resp = await http.get(uri).timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] == true && data['datos'] is Map) {
        final d = data['datos'] as Map<String, dynamic>;
        for (final f in _persona) {
          final v = d[f[0]];
          if (v != null) _c(f[0]).text = '$v';
        }
      }
      // El sistema ya conoce al profesor: rellena su nombre si aún no está.
      if (_c('NOMBRE').text.trim().isEmpty) {
        final n = await SessionStore.name();
        if (n != null && n.trim().isNotEmpty) {
          _c('NOMBRE').text = n.trim();
        }
      }
      // Materias del profesor (para autocompletar el periodo del contrato).
      try {
        final ug = Uri.parse(guardianUrl).replace(queryParameters: {
          'accion': 'mis_grupos',
          'correo': _correo,
        });
        final rg = await http.get(ug).timeout(const Duration(seconds: 30));
        final dg = jsonDecode(rg.body) as Map<String, dynamic>;
        if (dg['ok'] == true && dg['grupos'] is List) {
          _materias = (dg['grupos'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          // (ago-2026) BLOQUE CONJUNTO: las materias que se imparten juntas
          // comparten UN solo contrato — se colapsan en UNA entrada del
          // selector. El valor interno conserva la primera materia; el
          // backend expande a "A y B" con pago único al ver y al firmar.
          final vistosBloque = <String, int>{};
          final colapsadas = <Map<String, dynamic>>[];
          for (final m in _materias) {
            final blq = (m['bloqueConjunto'] ?? '').toString().trim();
            if (blq.isEmpty) {
              colapsadas.add(m);
              continue;
            }
            final idx = vistosBloque[blq];
            if (idx == null) {
              vistosBloque[blq] = colapsadas.length;
              m['bloqueNoms'] = <String>[(m['materia'] ?? '').toString()];
              colapsadas.add(m);
            } else {
              (colapsadas[idx]['bloqueNoms'] as List)
                  .add((m['materia'] ?? '').toString());
            }
          }
          _materias = colapsadas;
        }
      } catch (_) {}
      // Asignaturas que el profesor ya tiene contratadas (para marcarlas).
      try {
        final uc = Uri.parse(guardianUrl).replace(queryParameters: {
          'accion': 'contrato_mis_asignaturas',
          'correo': _correo,
        });
        final rc = await http.get(uc).timeout(const Duration(seconds: 30));
        final dc = jsonDecode(rc.body) as Map<String, dynamic>;
        if (dc['ok'] == true && dc['asignaturas'] is List) {
          _contratadas.clear();
          for (final a in (dc['asignaturas'] as List)) {
            final m = Map<String, dynamic>.from(a as Map);
            final nombre = (m['asignatura'] ?? '').toString();
            if (nombre.isNotEmpty) {
              _contratadas[_normMat(nombre)] = (m['estatus'] ?? '').toString();
            }
          }
        }
      } catch (_) {}
      // Si el profesor tiene una sola materia, se carga sola.
      if (_materias.length == 1) {
        _aplicarMateria(0, aviso: false);
      }
      // Estatus del contrato del profesor (si ya firmó alguno).
      try {
        final ue = Uri.parse(
            '$guardianUrl?accion=contrato_mi_estatus&correo=${Uri.encodeComponent(_correo)}');
        final re2 = await http.get(ue).timeout(const Duration(seconds: 20));
        final de = jsonDecode(re2.body) as Map<String, dynamic>;
        if (de['ok'] == true && de['tiene'] == true) _estatus = de;
      } catch (_) {}
    } catch (_) {
      // Sin conexión: el profesor puede capturar igual.
    }
    // Forma de pago: por defecto "POR ASIGNATURA" (contrato por asignatura).
    if (_c('FORMA_PAGO').text.trim().isEmpty) {
      _c('FORMA_PAGO').text = 'POR ASIGNATURA';
    }
    // Días de aviso previo: por defecto 15 días naturales (valor legal usual).
    if (_c('DIAS_AVISO').text.trim().isEmpty) {
      _c('DIAS_AVISO').text = '15';
    }
    // Perfil profesional: si va vacío, se propone una síntesis a partir de los
    // estudios capturados; el profesor puede ajustarla.
    if (_c('PERFIL').text.trim().isEmpty) {
      final est = _c('ESTUDIOS').text.trim();
      _c('PERFIL').text = est.isNotEmpty
          ? '$est, con experiencia docente y dominio de la asignatura'
          : 'Estudios afines a la asignatura, con experiencia docente';
    }
    if (mounted) setState(() => _cargando = false);
  }

  Map<String, String> _config() => Map<String, String>.from(_tipos[_tipoIdx]);

  // Lista de campos (además de la persona) según el tipo elegido.
  List<List<String>> _camposPeriodo() {
    final tipo = _config()['tipo'];
    if (tipo == 'trabajador') {
      return [..._trabajador, ..._vigencia, ..._pago, ..._firmaFecha];
    }
    if (tipo == 'mixta') {
      return [..._docencia, ..._vigencia, ..._vacaciones, ..._pago, ..._firmaFecha];
    }
    return [..._docencia, ..._vigencia, ..._pago, ..._firmaFecha];
  }

  // Arma el objeto de datos para preview/firmar.
  Map<String, String> _datos() {
    final out = <String, String>{};
    for (final f in _persona) {
      out[f[0]] = _c(f[0]).text.trim();
    }
    for (final f in _camposPeriodo()) {
      out[f[0]] = _c(f[0]).text.trim();
    }
    out['CORREO'] = _correo;
    final cfg = _config();
    if (cfg['tipo'] != 'trabajador') {
      out['SEMANAS_NUM'] = cfg['num'] ?? '';
      out['SEMANAS_TEXTO'] = cfg['texto'] ?? '';
    }
    return out;
  }

  Future<void> _guardarPersona() async {
    if (_correo.isEmpty) {
      _aviso('Tu sesión expiró. Vuelve a entrar.', error: true);
      return;
    }
    setState(() => _guardando = true);
    try {
      final body = <String, dynamic>{
        'accion': 'contrato_datos_set',
        'correo': _correo,
      };
      for (final f in _persona) {
        body[f[0]] = _c(f[0]).text.trim();
      }
      final r = await _post(body);
      if (r['ok'] == true) {
        _aviso('Tus datos quedaron guardados.');
      } else {
        _aviso('${r['error'] ?? 'No se pudieron guardar.'}', error: true);
      }
    } catch (e) {
      _aviso('No se pudo guardar: $e', error: true);
    }
    if (mounted) setState(() => _guardando = false);
  }

  Future<void> _verContrato() async {
    setState(() => _generando = true);
    try {
      final r = await _post({
        'accion': 'contrato_preview',
        'tipo': _config()['tipo'],
        'datos': _datos(),
      });
      if (r['ok'] == true &&
          r['url'] is String &&
          (r['url'] as String).isNotEmpty) {
        // Abre el PDF del contrato (enlace público). Los data: URIs se
        // bloquean en móvil, por eso antes salía en blanco.
        final uri = Uri.parse(r['url'] as String);
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else if (r['ok'] == true && r['html'] is String) {
        // Respaldo: si no vino url, intenta el data URI (solo funciona en web).
        final b64 = base64Encode(utf8.encode(r['html'] as String));
        final uri = Uri.parse('data:text/html;charset=utf-8;base64,$b64');
        await launchUrl(uri, webOnlyWindowName: '_blank');
      } else {
        _aviso('${r['error'] ?? 'No se pudo generar la vista.'}', error: true);
      }
    } catch (e) {
      _aviso('No se pudo abrir: $e', error: true);
    }
    if (mounted) setState(() => _generando = false);
  }

  Future<void> _firmar() async {
    final err = _validar();
    if (err != null) {
      _aviso(err, error: true);
      return;
    }
    final confirma = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Firmar contrato'),
        content: const Text(
            'Se generará tu contrato con tu firma digital registrada, la de la '
            'institución y los testigos, y se enviará a validación del '
            'administrador. Cuando lo valide, recibirás el PDF firmado en tu '
            'correo. ¿Deseas continuar?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: cessumRed),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Firmar')),
        ],
      ),
    );
    if (confirma != true) return;

    setState(() => _generando = true);
    try {
      final r = await _post({
        'accion': 'contrato_firmar',
        'tipo': _config()['tipo'],
        'datos': _datos(),
      });
      if (r['ok'] == true) {
        _folio = '${r['folio'] ?? ''}';
        if (mounted) setState(() {});
        _aviso('Contrato enviado a validación. Folio: $_folio');
      } else {
        _aviso('${r['error'] ?? 'No se pudo firmar.'}', error: true);
      }
    } catch (e) {
      _aviso('No se pudo firmar: $e', error: true);
    }
    if (mounted) setState(() => _generando = false);
  }

  // Extrae [día, mes, año] de una fecha ISO o de texto inglés (GMT).
  List<int>? _dmy(String s) {
    s = s.trim();
    if (s.isEmpty) return null;
    final iso = RegExp(r'(\d{4})-(\d{2})-(\d{2})').firstMatch(s);
    if (iso != null) {
      return [int.parse(iso.group(3)!), int.parse(iso.group(2)!), int.parse(iso.group(1)!)];
    }
    const mesIng = {
      'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
      'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12
    };
    final low = s.toLowerCase();
    for (final e in mesIng.entries) {
      final idx = low.indexOf(e.key);
      if (idx >= 0) {
        final resto = s.substring(idx + 3);
        final nums = RegExp(r'\d+')
            .allMatches(resto)
            .map((m) => int.parse(m.group(0)!))
            .toList();
        int? dia;
        int? anio;
        for (final n in nums) {
          if (n >= 1000 && anio == null) {
            anio = n;
          } else if (dia == null && n >= 1 && n <= 31) {
            dia = n;
          }
          if (dia != null && anio != null) break;
        }
        if (dia != null && anio != null) return [dia, e.value, anio];
      }
    }
    return null;
  }

  String _etiquetaMateria(Map<String, dynamic> m) {
    String g(String k) => (m[k] ?? '').toString().trim();
    final sub = <String>[];
    if (g('generacion').isNotEmpty) sub.add('Gen. ${g('generacion')}');
    if (g('grupo').isNotEmpty) sub.add(g('grupo'));
    final base = g('materia').isEmpty ? 'Materia' : g('materia');
    return sub.isEmpty ? base : '$base · ${sub.join(' · ')}';
  }

  // Llena el periodo del contrato a partir de una materia del profesor.
  void _aplicarMateria(int idx, {bool aviso = true}) {
    if (idx < 0 || idx >= _materias.length) return;
    final m = _materias[idx];
    String g(String k) => (m[k] ?? '').toString().trim();

    _c('PROGRAMA').text = g('programa');
    _c('ASIGNATURA').text = g('materia');
    final modal = g('modalidad').isNotEmpty ? g('modalidad') : g('tipoSesiones');
    if (modal.isNotEmpty) _c('SISTEMA').text = modal;
    if (g('horas').isNotEmpty) _c('HORAS').text = g('horas');

    // Monto del contrato (tarifa institucional que calcula el Guardián).
    // La plantilla del contrato ya antepone el signo y agrega "pesos 00/100",
    // por eso aquí se limpia para no duplicar el signo ni las palabras.
    final montoNum = (m['montoContratoNum'] is num)
        ? (m['montoContratoNum'] as num)
        : num.tryParse('${m['montoContratoNum'] ?? ''}') ?? 0;
    if (montoNum > 0) _c('MONTO').text = _fmtMonto(montoNum);
    var letra = g('montoContratoLetra');
    final pIdx = letra.toUpperCase().indexOf(' PESOS');
    if (pIdx >= 0) letra = letra.substring(0, pIdx);
    letra = letra.trim().toLowerCase();
    if (letra.isNotEmpty) _c('MONTO_LETRA').text = letra;

    final ini = _dmy(g('inicio'));
    final fin = _dmy(g('termino'));
    if (ini != null) {
      _c('VIG_DIA_INI').text = '${ini[0]}';
      _c('VIG_MES_INI').text = '${ini[1]}';
      _c('VIG_ANIO_INI').text = '${ini[2]}';
    }
    if (fin != null) {
      _c('VIG_DIA_FIN').text = '${fin[0]}';
      _c('VIG_MES_FIN').text = '${fin[1]}';
      _c('VIG_ANIO_FIN').text = '${fin[2]}';
      // Día de pago = a más tardar 15 días después del término de la asignatura.
      try {
        final fechaFin = DateTime(fin[2], fin[1], fin[0]);
        final pago = fechaFin.add(const Duration(days: 15));
        final mm = pago.month.toString().padLeft(2, '0');
        final dd = pago.day.toString().padLeft(2, '0');
        _c('DIA_PAGO').text = '$dd/$mm/${pago.year}';
      } catch (_) {}
    }

    // Número de semanas -> elige el tipo de contrato (Docencia · N) más cercano.
    if (ini != null && fin != null) {
      final da = DateTime(ini[2], ini[1], ini[0]);
      final db = DateTime(fin[2], fin[1], fin[0]);
      final dias = db.difference(da).inDays;
      if (dias > 0) {
        final semanas = (dias / 7).round();
        int mejor = _tipoIdx;
        int mejorDif = 9999;
        for (int i = 0; i < _tipos.length; i++) {
          if (_tipos[i]['tipo'] != 'docencia') continue;
          final num = int.tryParse(_tipos[i]['num'] ?? '') ?? 0;
          final dif = (num - semanas).abs();
          if (dif < mejorDif) {
            mejorDif = dif;
            mejor = i;
          }
        }
        _tipoIdx = mejor;
      }
    }

    // Fecha de firma = hoy.
    final hoy = DateTime.now();
    _c('FIRMA_DIA').text = '${hoy.day}';
    _c('FIRMA_MES').text = '${hoy.month}';
    _c('FIRMA_ANIO').text = '${hoy.year}';

    setState(() => _materiaIdx = idx);
    if (aviso) {
      _aviso('Periodo y monto cargados desde la materia. Revisa antes de firmar.');
    }
  }

  // Formatea un numero como "4,245.43" (sin simbolo; la plantilla agrega el signo).
  String _fmtMonto(num n) {
    final fixed = n.toStringAsFixed(2);
    final p = fixed.split('.');
    final ent = p[0];
    final b = StringBuffer();
    for (int i = 0; i < ent.length; i++) {
      if (i > 0 && (ent.length - i) % 3 == 0) b.write(',');
      b.write(ent[i]);
    }
    return '${b.toString()}.${p[1]}';
  }

  void _aviso(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? cessumRed : cessumGold,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final oscuro = cessumIsDark(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi contrato'),
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _aviso0(oscuro),
                const SizedBox(height: 16),
                if (_estatus != null) ...[
                  _tarjetaEstatus(),
                  const SizedBox(height: 16),
                ],

                _titulo('1. Tus datos', Icons.person),
                const SizedBox(height: 8),
                ..._persona.map((f) => _campo(f[0], f[1])),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _guardando ? null : _guardarPersona,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: cessumRed,
                      side: const BorderSide(color: cessumRed),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: _guardando
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: cessumRed))
                        : const Icon(Icons.save_outlined),
                    label: const Text('Guardar mis datos'),
                  ),
                ),

                const SizedBox(height: 20),
                _titulo('2. Tipo de contrato', Icons.description),
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  initialValue: _tipoIdx,
                  decoration: _dec('Tipo'),
                  items: [
                    for (int i = 0; i < _tipos.length; i++)
                      DropdownMenuItem(value: i, child: Text(_tipos[i]['label']!)),
                  ],
                  onChanged: (v) => setState(() => _tipoIdx = v ?? 0),
                ),

                const SizedBox(height: 20),
                _titulo('3. Datos del periodo', Icons.edit_calendar),
                const SizedBox(height: 8),
                if (_materias.isNotEmpty) ...[
                  if (_materias.length > 1)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cessumGold.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border:
                            Border.all(color: cessumGold.withValues(alpha: 0.40)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline, color: cessumGold, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
'Tienes ${_materias.length} contrato(s) por asignar y ya '
                              'firmaste ${_contratadas.length}. Las materias '
                              'de un BLOQUE CONJUNTO aparecen unidas y '
                              'comparten UN solo contrato con pago único. '
                              'Elige cada entrada (las firmadas llevan ✓), '
                              'genera su contrato y repite con la siguiente.',
                              style: TextStyle(
                                  fontSize: 12.5, color: cessumInk(context)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  DropdownButtonFormField<int>(
                    initialValue: _materiaIdx,
                    isExpanded: true,
                    decoration: _dec('Materia de este contrato'),
                    items: [
                      for (int i = 0; i < _materias.length; i++)
                        DropdownMenuItem(
                          value: i,
                          child: Text(
                            (_contratadas.containsKey(_normMat(
                                        _nombreContrato(_materias[i])))
                                    ? '✓ '
                                    : '• ') +
                                (_esBloque(_materias[i])
                                    ? '${_nombreContrato(_materias[i])} · '
                                        '${_materias[i]['generacion'] ?? ''} · '
                                        '${_materias[i]['grupo'] ?? ''} '
                                        '(bloque conjunto · UN contrato)'
                                    : _etiquetaMateria(_materias[i])) +
                                (_contratadas.containsKey(_normMat(
                                        _nombreContrato(_materias[i])))
                                    ? '  (con contrato)'
                                    : ''),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (v) {
                      if (v != null) _aplicarMateria(v);
                    },
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10, left: 2),
                    child: Text(
                      'Elige una materia y se llenan solos el programa, la '
                      'asignatura, el sistema y las fechas de inicio y fin. '
                      'Cada materia lleva su propio contrato.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ),
                ],
                ..._camposPeriodo().map((f) => _campo(f[0], f[1])),

                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _generando ? null : _verContrato,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: cessumGold,
                      side: const BorderSide(color: cessumGold),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: const Icon(Icons.menu_book_outlined),
                    label: const Text('Ver / leer el contrato'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _generando ? null : _firmar,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cessumRed,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: _generando
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.draw_outlined),
                    label: const Text('Firmar contrato'),
                  ),
                ),

                if (_folio.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: cessumGold.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: cessumGold.withValues(alpha: 0.35)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.verified, color: cessumGold, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Contrato enviado a validación. Folio: $_folio. '
                            'Recibirás el PDF firmado en tu correo cuando el '
                            'administrador lo valide.',
                            style: TextStyle(
                                fontSize: 13, color: cessumMuted(context)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 28),
              ],
            ),
    );
  }

  Widget _aviso0(bool oscuro) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cessumRed.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cessumRed.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline, color: cessumRed, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Llena tus datos una vez (se guardan). Elige el tipo, captura el '
                'periodo, lee el contrato y fírmalo. Necesitas tu firma registrada.',
                style: TextStyle(fontSize: 12.5, height: 1.35, color: cessumMuted(context)),
              ),
            ),
          ],
        ),
      );

  Future<void> _abrirUrl(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return;
    try {
      await launchUrl(uri,
          webOnlyWindowName: '_blank', mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Widget _tarjetaEstatus() {
    final e = _estatus!;
    final estatus = (e['estatus'] ?? '').toString();
    final pdfUrl = (e['pdfUrl'] ?? '').toString();
    final folio = (e['folio'] ?? '').toString();
    final motivo = (e['motivo'] ?? '').toString();
    Color color;
    IconData icono;
    String titulo;
    String detalle;
    if (estatus == 'Validado') {
      color = const Color(0xFF1E8E3E);
      icono = Icons.verified;
      titulo = 'Tu contrato está validado';
      detalle = 'Folio $folio. Ya puedes descargar tu PDF firmado.';
    } else if (estatus == 'Rechazado') {
      color = cessumRed;
      icono = Icons.error_outline;
      titulo = 'Tu contrato necesita ajustes';
      detalle = motivo.isNotEmpty
          ? 'Motivo: $motivo. Corrige y vuelve a firmar.'
          : 'Corrige tus datos y vuelve a firmar.';
    } else {
      color = cessumGold;
      icono = Icons.hourglass_bottom;
      titulo = 'Tu contrato está en validación';
      detalle = 'Folio $folio. Te avisaremos cuando el administrador lo valide.';
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icono, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  titulo,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: color,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            detalle,
            style: TextStyle(fontSize: 13, color: cessumMuted(context)),
          ),
          if (pdfUrl.isNotEmpty && estatus != 'Rechazado') ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 11),
                ),
                onPressed: () => _abrirUrl(pdfUrl),
                icon: const Icon(Icons.picture_as_pdf, size: 18),
                label: const Text('Descargar mi contrato (PDF)'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Instituciones bancarias (nombre legal CNBV) para la lista desplegable.
  static const List<String> _bancos = [
    'BBVA México, S.A.',
    'Banco Santander México, S.A.',
    'Banco Nacional de México, S.A. (Banamex)',
    'Banco Mercantil del Norte, S.A. (Banorte)',
    'HSBC México, S.A.',
    'Scotiabank Inverlat, S.A.',
    'Banco Inbursa, S.A.',
    'Banco Azteca, S.A.',
    'Banco Regional, S.A. (Banregio)',
    'Banca Afirme, S.A.',
    'Banco del Bajío, S.A.',
    'BanCoppel, S.A.',
    'Banco Ve por Más, S.A.',
    'Banca Mifel, S.A.',
    'Banco Multiva, S.A.',
    'Banco Compartamos, S.A.',
    'Banco del Bienestar, S.N.C.',
    'Banco Monex, S.A.',
    'Banco Actinver, S.A.',
    'Banco Base, S.A.',
    'Banco BanCrea, S.A.',
    'Banco Autofin México, S.A.',
    'Hey, Banco, S.A. (Banregio)',
    'Nu México, S.A.',
    'STP (Sistema de Transferencias y Pagos), S.A. de C.V.',
    'Mercado Pago W, S.A. de C.V., SOFIPO',
    'Otra institución bancaria',
  ];

  String? _validar() {
    if (_c('NOMBRE').text.trim().isEmpty) return 'Falta tu nombre completo.';
    final rfc = _c('RFC').text.trim().toUpperCase();
    final curp = _c('CURP').text.trim().toUpperCase();
    final clabe = _c('CLABE').text.trim();
    if (rfc.isNotEmpty &&
        !RegExp(r'^[A-ZÑ&]{3,4}\d{6}[A-Z0-9]{3}$').hasMatch(rfc)) {
      return 'El RFC no tiene un formato válido (12 o 13 caracteres).';
    }
    if (curp.isNotEmpty &&
        !RegExp(r'^[A-Z]{4}\d{6}[HM][A-Z]{5}[A-Z0-9]\d$').hasMatch(curp)) {
      return 'La CURP no tiene un formato válido (deben ser 18 caracteres).';
    }
    // (ago-18) SE LIMPIA ANTES DE VALIDAR. Muchos la pegan del banco con
    // espacios o guiones: son 18 dígitos, pero la expresión los rechazaba y
    // el mensaje decía "18 dígitos" cuando la persona contaba 18 y no
    // entendía qué estaba mal.
    final clabeLimpia = clabe.replaceAll(RegExp(r'[\s-]'), '');
    if (clabeLimpia.isNotEmpty && !RegExp(r'^\d{18}$').hasMatch(clabeLimpia)) {
      final noDigitos = clabeLimpia.replaceAll(RegExp(r'\d'), '');
      if (noDigitos.isNotEmpty) {
        return 'La CLABE solo lleva números, y la tuya trae: '
            '${noDigitos.split('').toSet().join(' ')}';
      }
      return 'La CLABE debe tener 18 dígitos y escribiste '
          '${clabeLimpia.length}. Revisa que no falte ni sobre ninguno, '
          'incluidos los ceros del principio y del final.';
    }
    // Campos obligatorios: no se permiten espacios en blanco en el contrato.
    final obligatorios = <String, String>{
      'NOMBRE': 'el nombre completo',
      'RFC': 'el RFC',
      'CURP': 'la CURP',
      'ESTUDIOS': 'los estudios',
      'PERFIL': 'el perfil profesional (breve síntesis curricular)',
      'DOMICILIO': 'el domicilio',
      'CUENTA': 'la cuenta bancaria',
      'CLABE': 'la CLABE interbancaria',
      'BANCO': 'la institución bancaria',
      'TITULAR': 'el titular de la cuenta',
      'MONTO': 'el monto',
      'MONTO_LETRA': 'el monto con letra',
      'FORMA_PAGO': 'la forma de pago',
      'DIA_PAGO': 'el día de pago',
      'VIG_DIA_INI': 'el inicio de vigencia',
      'VIG_MES_INI': 'el inicio de vigencia',
      'VIG_ANIO_INI': 'el inicio de vigencia',
      'VIG_DIA_FIN': 'el fin de vigencia',
      'VIG_MES_FIN': 'el fin de vigencia',
      'VIG_ANIO_FIN': 'el fin de vigencia',
    };
    for (final e in obligatorios.entries) {
      if (_c(e.key).text.trim().isEmpty) return 'Falta ${e.value}.';
    }
    return null;
  }

  Widget _titulo(String t, IconData ic) => Row(
        children: [
          Icon(ic, size: 18, color: cessumRed),
          const SizedBox(width: 8),
          Text(t,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: cessumIsDark(context) ? Colors.white : cessumInk(context))),
        ],
      );

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: cessumRed, width: 1.6),
        ),
      );

  // Texto de ayuda por campo: orienta al profesor y da soporte jurídico.
  static const Map<String, String> _ayuda = {
    'NOMBRE':
        'Nombre completo del profesionista, tal como aparece en su identificación oficial (INE).',
    'RFC':
        'RFC a 13 caracteres con homoclave, conforme a su Constancia de Situación Fiscal del SAT.',
    'CURP': 'CURP a 18 caracteres, igual que en el documento oficial.',
    'ESTUDIOS':
        'Grado máximo de estudios concluido (ej. Maestría en Educación).',
    'TITULO': 'Documento que acredita los estudios señalados. Para licenciatura es "título"; para maestría o doctorado es "certificado".',
    'CEDULA':
        'Número de cédula profesional, si cuenta con ella. Si no la tiene, déjelo vacío.',
    'EXPEDIDO_POR':
        'Institución que expidió el título o la cédula (ej. SEP, universidad).',
    'DOMICILIO':
        'Domicilio completo para oír y recibir notificaciones: calle, número, colonia, ciudad y C.P.',
    'CUENTA': 'Número de cuenta bancaria donde recibirá el pago.',
    'CLABE':
        'CLABE interbancaria de 18 dígitos (la usa el banco para las transferencias).',
    'BANCO':
        'Institución bancaria de su cuenta (nombre legal). Debe coincidir con la cuenta y la CLABE.',
    'TITULAR':
        'Nombre del titular de la cuenta. Debe ser, de preferencia, el mismo profesionista.',
    'VIG_DIA_INI': 'Día en que inicia la vigencia del contrato.',
    'VIG_MES_INI': 'Mes en que inicia la vigencia (número, 1 a 12).',
    'VIG_ANIO_INI': 'Año en que inicia la vigencia (ej. 2026).',
    'VIG_DIA_FIN': 'Día en que termina la vigencia del contrato.',
    'VIG_MES_FIN': 'Mes en que termina la vigencia (número, 1 a 12).',
    'VIG_ANIO_FIN': 'Año en que termina la vigencia (ej. 2026).',
    'FIRMA_DIA': 'Día en que se firma el contrato.',
    'FIRMA_MES': 'Mes en que se firma (número, 1 a 12).',
    'FIRMA_ANIO': 'Año en que se firma (ej. 2026).',
    'MONTO': 'Importe total a pagar, en cifra (ej. 4,245.43).',
    'MONTO_LETRA':
        'El mismo importe con letra (ej. cuatro mil doscientos cuarenta y cinco pesos 43/100 M.N.). En caso de diferencia con la cifra, prevalece la cantidad con letra.',
    'FORMA_PAGO':
        'Forma en que se cubre el pago. Por defecto "POR ASIGNATURA": un pago por impartir la asignatura completa.',
    'DIA_PAGO':
        'Fecha límite de pago. Se calcula sola: a más tardar 15 días después de terminada la asignatura.',
    'DIAS_AVISO':
        'Días de aviso previo: días naturales con que cualquiera de las partes debe avisar por escrito para terminar el contrato antes de su vencimiento (ej. 15).',
    'PROGRAMA': 'Programa académico en el que impartirá (ej. Maestría en Educación).',
    'ASIGNATURA': 'Nombre de la asignatura o materia que impartirá.',
    'SISTEMA': 'Sistema o modalidad del programa (ej. No escolarizado, Mixto).',
    'HORAS': 'Número total de horas de la asignatura.',
    'VAC1_DIA_INI': 'Solo Mixta: día de inicio del 1er periodo vacacional.',
    'VAC1_MES_INI': 'Solo Mixta: mes de inicio del 1er periodo vacacional.',
    'VAC1_DIA_FIN': 'Solo Mixta: día de fin del 1er periodo vacacional.',
    'VAC1_MES_FIN': 'Solo Mixta: mes de fin del 1er periodo vacacional.',
    'VAC2_DIA_INI': 'Solo Mixta: día de inicio del 2º periodo vacacional.',
    'VAC2_MES_INI': 'Solo Mixta: mes de inicio del 2º periodo vacacional.',
    'VAC2_DIA_FIN': 'Solo Mixta: día de fin del 2º periodo vacacional.',
    'VAC2_MES_FIN': 'Solo Mixta: mes de fin del 2º periodo vacacional.',
    'VAC3_DIA_INI': 'Solo Mixta: día de inicio del 3er periodo vacacional.',
    'VAC3_MES_INI': 'Solo Mixta: mes de inicio del 3er periodo vacacional.',
    'VAC3_DIA_FIN': 'Solo Mixta: día de fin del 3er periodo vacacional.',
    'VAC3_MES_FIN': 'Solo Mixta: mes de fin del 3er periodo vacacional.',
    'SERVICIOS': 'Descripción de los servicios profesionales contratados.',
    'AREA': 'Área o departamento donde prestará los servicios.',
    'PERFIL': 'Breve síntesis curricular: tu grado, formación y experiencia que respaldan impartir la asignatura (ej. Maestría en Educación, con experiencia docente).',
    'PERIODO_INI': 'Fecha de inicio del periodo de prestación de servicios.',
    'PERIODO_FIN': 'Fecha de fin del periodo de prestación de servicios.',
    'MODALIDAD': 'Modalidad del servicio: presencial, remota o híbrida.',
    'ACTIVIDADES': 'Actividades concretas que realizará.',
    'OBLIGACIONES': 'Obligaciones específicas que asume el profesionista.',
  };

  Widget _campo(String key, String label) {
    if (key == 'BANCO') return _campoBanco(label);
    final multi = _multilinea.contains(key);
    final readOnly = key == 'DIA_PAGO';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: _c(key),
        readOnly: readOnly,
        decoration: _dec(label).copyWith(
          helperText: key == 'CLABE'
              ? _ayudaClabe()
              : _ayuda[key],
          helperMaxLines: 4,
          helperStyle: key == 'CLABE' && _c('CLABE').text.trim().length == 18
              ? const TextStyle(color: Color(0xFF1E8E3E), fontWeight: FontWeight.w600)
              : null,
          counterText: key == 'CLABE' ? '' : null,
        ),
        maxLines: multi ? 3 : 1,
        // La CLABE y la cuenta son NÚMEROS de 18 y hasta 20 dígitos: se
        // filtran letras y símbolos en el teclado, para que el error no
        // aparezca hasta el final.
        inputFormatters: (key == 'CLABE')
            ? [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(18),
              ]
            : (key == 'CUENTA')
                ? [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(20),
                  ]
                : (key == 'RFC' || key == 'CURP')
                    ? [LengthLimitingTextInputFormatter(20)]
                    : null,
        keyboardType: (key == 'CLABE' || key == 'CUENTA')
            ? TextInputType.number
            : (multi ? TextInputType.multiline : TextInputType.text),
        onChanged: (key == 'CLABE') ? (_) => setState(() {}) : null,
      ),
    );
  }

  /// (ago-18) Cuenta los dígitos en vivo. Antes el docente escribía 17 o 19
  /// sin notarlo y el error solo aparecía al firmar, sin decirle cuántos
  /// llevaba.
  String _ayudaClabe() {
    final n = _c('CLABE').text.trim().length;
    if (n == 0) return _ayuda['CLABE'] ?? '';
    if (n == 18) return 'Listo: 18 de 18 dígitos.';
    return '$n de 18 dígitos. ${n < 18 ? 'Faltan ${18 - n}.' : ''}';
  }

  Widget _campoBanco(String label) {
    final actual = _c('BANCO').text.trim();
    final valor = _bancos.contains(actual) ? actual : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DropdownButtonFormField<String>(
        value: valor,
        isExpanded: true,
        decoration: _dec(label).copyWith(
          helperText: _ayuda['BANCO'],
          helperMaxLines: 3,
        ),
        items: _bancos
            .map((b) => DropdownMenuItem<String>(
                  value: b,
                  child: Text(b, overflow: TextOverflow.ellipsis),
                ))
            .toList(),
        onChanged: (v) {
          if (v != null) setState(() => _c('BANCO').text = v);
        },
      ),
    );
  }
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'helpers.dart';
import 'foto_web_picker.dart';
import 'student_profile.dart';
import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'envio_titulo_screen.dart';
import 'titulacion_screen.dart';
import 'mi_expediente_titulacion_screen.dart';
import 'tesis_convenio_screen.dart';

// =====================================================================
//  NORMA INSTITUCIONAL — RUTA POR OPCION DE TITULACION
//  ---------------------------------------------------------------------
//  UNICO lugar donde se define que pasos ve cada alumno. Si manana cambia
//  el reglamento, se edita ESTA tabla y nada mas.
//
//    conJurado : se designan presidente, secretario y vocal (sinodos).
//    conExamen : hay examen profesional / replica ante el jurado.
//
//  Acuerdo de Vicerrectoria (jul-2026):
//    - Tesis ................................ jurado SI, examen SI
//    - Produccion academica ................. jurado SI, examen SI
//    - Excelencia academica ................. jurado NO, examen NO
//    - Creditos de nivel superior en CESSUM . jurado NO, examen NO
//    - Estancia postdoctoral ................ jurado NO, examen NO (dictamen)
//
//  Las VENTANILLAS (1 autenticacion y 2 certificacion) y la ENTREGA DEL
//  TITULO aplican a TODAS las opciones, sin excepcion.
// =====================================================================
class _RutaTitulacion {
  final bool conJurado;
  final bool conExamen;
  const _RutaTitulacion({required this.conJurado, required this.conExamen});
}

const _RutaTitulacion _rutaConExamen =
    _RutaTitulacion(conJurado: true, conExamen: true);
const _RutaTitulacion _rutaSinExamen =
    _RutaTitulacion(conJurado: false, conExamen: false);

/// Devuelve la ruta normada para la opcion de titulacion elegida.
/// Se compara en minusculas y por fragmento, para tolerar variantes de
/// captura ("Tesis", "tesis ", "Titulacion por tesis", etc.).
_RutaTitulacion _rutaDe(String opcion) {
  final o = opcion.trim().toLowerCase();
  if (o.contains('tesis')) return _rutaConExamen;
  if (o.contains('produc')) return _rutaConExamen; // Produccion academica
  return _rutaSinExamen; // Excelencia, Creditos, Estancia postdoctoral
}

/// Orden oficial de etapas (espejo de kEtapasTitulacion del panel admin).
/// Sirve para saber si una etapa ya quedo atras. Las etapas de excepcion
/// ("Examen suspendido", "Rechazada") NO van aqui: se tratan aparte.
const List<String> _kEtapasOrden = [
  'Solicitud en validación',
  'Integración de expediente',
  'Expediente en revisión',
  'Expediente aprobado',
  'Sínodos asignados',
  'Examen programado',
  'Ventanilla 1: autenticación',
  'Ventanilla 2: certificación',
  'Titulado',
];

const int _iExpedienteAprobado = 3;
const int _iVentanilla1 = 6;
const int _iVentanilla2 = 7;
const int _iTitulado = 8;

/// Alumno: "Mi titulacion paso a paso". La ruta que se dibuja depende de la
/// OPCION DE TITULACION del expediente: a quien no se titula por tesis no se
/// le muestran jurado ni examen profesional.
class MiTitulacionScreen extends StatefulWidget {
  const MiTitulacionScreen({super.key});

  @override
  State<MiTitulacionScreen> createState() => _MiTitulacionScreenState();
}

class _MiTitulacionScreenState extends State<MiTitulacionScreen> {
  bool _cargando = true;
  bool _guardando = false;
  String? _error;
  StudentProfile? _perfil;
  String _correo = '';
  Map<String, dynamic>? _exp;
  Map<String, dynamic>? _malla;
  // (25-sep) Siguiente paso: quién tiene la pelota y qué falta (motor de titulación).
  Map<String, dynamic>? _motor;
  // (25-sep) Modalidades y costos: precios para SU programa y generación, y
  // su elegibilidad (excelencia no disponible si reprobó alguna materia).
  Map<String, dynamic>? _precios;
  Map<String, dynamic>? _eleg;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final p = await StudentProfile.load();
      if (p == null) {
        setState(() {
          _cargando = false;
          _error = 'Completa tu perfil para ver tu titulación.';
        });
        return;
      }
      _perfil = p;
      _correo = await SessionStore.validEmail() ?? '';
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'titulacion_de',
        'matricula': p.matricula,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      _exp = data['expediente'] is Map
          ? Map<String, dynamic>.from(data['expediente'] as Map)
          : null;
      _malla = data['malla'] is Map
          ? Map<String, dynamic>.from(data['malla'] as Map)
          : null;
      _motor = data['motor'] is Map
          ? Map<String, dynamic>.from(data['motor'] as Map)
          : null;
      _precios = data['preciosTitulacion'] is Map
          ? Map<String, dynamic>.from(data['preciosTitulacion'] as Map)
          : null;
      _eleg = data['elegibilidad'] is Map
          ? Map<String, dynamic>.from(data['elegibilidad'] as Map)
          : null;
    } catch (e) {
      _error = 'No se pudo cargar tu titulación. Intenta de nuevo.';
    }
    if (mounted) setState(() => _cargando = false);
  }

  Future<void> _abrirGestion() async {
    final p = _perfil;
    if (p == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TitulacionScreen(perfil: p, correo: _correo),
      ),
    );
    _cargar();
  }

  Future<void> _abrirTesis() async {
    final p = _perfil;
    if (p == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TesisConvenioScreen(
          matricula: p.matricula,
          nombre: p.nombreCompleto,
          programa: _s('programa').isNotEmpty ? _s('programa') : p.programa,
          generacion:
              _s('generacion').isNotEmpty ? _s('generacion') : p.generacion,
          correo: _correo,
          rol: 'alumno',
        ),
      ),
    );
    _cargar();
  }

  // -------- helpers de estado --------
  String _s(String k) => (_exp?[k] ?? '').toString().trim();

  String get _opcion => _s('opcion');

  _RutaTitulacion get _ruta => _rutaDe(_opcion);

  bool get _esTesis => _opcion.toLowerCase().contains('tesis');

  /// Posicion de la etapa actual dentro del flujo oficial. -1 si la etapa
  /// esta vacia o es de excepcion.
  int get _etapaIdx {
    final e = _s('etapa');
    if (e.isEmpty) return -1;
    return _kEtapasOrden.indexOf(e);
  }

  bool get _etapaSuspendida => _s('etapa') == 'Examen suspendido';
  bool get _etapaRechazada => _s('etapa') == 'Rechazada';

  List<Map<String, dynamic>> get _docs {
    final d = _exp?['documentos'];
    if (d is List) {
      return d.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }

  bool get _docsCompletos {
    final obl = _docs.where((x) => x['obligatorio'] == true).toList();
    if (obl.isEmpty) return false;
    return obl.every((x) => (x['estatus'] ?? '').toString() == 'Aprobado');
  }

  bool get _sinodosListos =>
      _s('presidente').isNotEmpty &&
      _s('secretario').isNotEmpty &&
      _s('vocal').isNotEmpty;

  bool get _hayEntrega => _s('entregaFecha').isNotEmpty;

  // Compromiso institucional: la coordinación resuelve cada paso en 72 h.
  // Las ventanillas 1 y 2 se excluyen: son trámites ante la autoridad
  // educativa y tardan más, no depende de nosotros.
  static const int _kHorasCompromiso = 72;

  bool get _enVentanilla {
    final e = _s('etapa');
    return e == 'Ventanilla 1: autenticación' ||
        e == 'Ventanilla 2: certificación';
  }

  bool get _etapaFinal {
    final e = _s('etapa');
    return e == 'Titulado' || e == 'Rechazada';
  }

  double get _horasParado {
    final ms = (_exp?['actualizadoMs'] ?? _exp?['solicitudMs'] ?? 0);
    final n = ms is num ? ms.toInt() : int.tryParse(ms.toString()) ?? 0;
    if (n <= 0) return 0;
    return DateTime.now()
            .difference(DateTime.fromMillisecondsSinceEpoch(n))
            .inMinutes /
        60.0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Mi titulación'),
        actions: [
          IconButton(
              onPressed: _cargando ? null : _cargar,
              icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _cargando
          ? const CessumSkeletonList()
          : _error != null
              ? Center(
                  child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_error!, textAlign: TextAlign.center),
                ))
              : _contenido(),
    );
  }

  Widget _contenido() {
    final pasos = _construirPasos();
    final hechos = pasos.where((p) => p['estado'] == 'done').length;
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          _encabezado(pasos.length, hechos),
          const SizedBox(height: 14),
          if (_motor != null && '${_motor!['quien']}' != 'cerrado') ...[
            _tarjetaSiguientePaso(),
            const SizedBox(height: 14),
          ],
          // (2-sep) EL BOTÓN PRINCIPAL ESTABA HASTA ABAJO, después de todos
          // los pasos: había que desplazar toda la pantalla para encontrarlo
          // y no se entendía que ahí se entra a la solicitud y al expediente.
          // Ahora va arriba, en cuanto se abre la pantalla.
          _botonPrincipal(),
          const SizedBox(height: 14),
          if (_nivelTitulacion.isNotEmpty) ...[
            _apartadoModalidades(),
            const SizedBox(height: 14),
          ],
          if (_hayEntrega) _tarjetaEntrega(),
          if (_s('etapa') == 'Entrega de título' ||
              (_s('tituloEntregaModo').isNotEmpty))
            _tarjetaEntregaTitulo(),
          _botonRecibirPorEnvio(),
          if (!_hayEntrega && !_enVentanilla && !_etapaFinal && _exp != null)
            _tarjetaTimer(),
          if (_etapaSuspendida || _etapaRechazada) _avisoExcepcion(),
          if (_exp == null) _avisoSinSolicitud(),
          // (8-sep) PUERTA ÚNICA A LA TITULACIÓN.
          // «Mi expediente de titulación» era un acceso paralelo en el menú,
          // y sus documentos viven en otra hoja que solo se copia a la de
          // Titulación al presentar la solicitud. Después de ese momento esa
          // pantalla ya no sirve para entregar nada. Por eso deja de ser una
          // puerta propia y se ofrece únicamente aquí, mientras adelantar
          // documentos todavía tiene sentido.
          // (14-sep) El botón se muestra SIEMPRE: el Guardián ya escribe en
          // Titulación cuando hay solicitud, así que el expediente sirve
          // también después de solicitar. Cambia solo el texto.
          _botonAdelantarExpediente(),
          if (_exp != null && _opcion.isNotEmpty && !_ruta.conExamen)
            _avisoSinExamen(),
          ...List.generate(pasos.length, (i) => _tarjetaPaso(i + 1, pasos[i])),
          const SizedBox(height: 8),
          if (_esTesis) ...[
            const SizedBox(height: 8),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumGold,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              icon: const Icon(Icons.handshake),
              label: const Text('Mi tesis · convenio y seguimiento'),
              onPressed: _abrirTesis,
            ),
          ],
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  // (2-sep) Botón principal de la pantalla. Va arriba y dice INICIAR, que es
  // lo que la persona viene a hacer; "Gestionar" no se entendía. El texto
  // cambia según dónde esté: sin expediente, con uno rechazado (puede
  // presentar otra solicitud) o con el trámite en marcha.
  /// (25-sep) «Tu siguiente paso»: le dice al alumno si le toca a él (y
  /// qué, con el monto del pago) o si su expediente está con CESSUM o la SEC.
  Widget _tarjetaSiguientePaso() {
    final m = _motor!;
    final quien = '${m['quien']}';
    final faltan = ((m['faltan'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final costo = (m['costo'] as num?) ?? 0;
    final tuyo = quien == 'tu';
    final Color c = tuyo
        ? cessumRed
        : quien == 'concluido'
            ? const Color(0xFF1E7F52)
            : cessumGold;
    String pesos(num n) {
      final t = n.round().toString();
      final b = StringBuffer();
      for (var i = 0; i < t.length; i++) {
        if (i > 0 && (t.length - i) % 3 == 0) b.write(',');
        b.write(t[i]);
      }
      return '\$$b';
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.withValues(alpha: 0.5), width: 1.4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(tuyo ? Icons.assignment_late_outlined : (quien == 'concluido' ? Icons.celebration : Icons.hourglass_top), color: c),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              tuyo
                  ? 'Tu siguiente paso'
                  : quien == 'sec'
                      ? 'En trámite ante la SEC'
                      : quien == 'concluido'
                          ? '¡Tu titulación concluyó!'
                          : 'Tu expediente está con CESSUM',
              style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: c),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        Text('${m['texto'] ?? ''}', style: const TextStyle(fontSize: 13.5, height: 1.4)),
        if (faltan.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final f in faltan)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(f['rechazado'] == true ? Icons.replay : Icons.upload_file, size: 17, color: c),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${f['etiqueta']}'
                    '${'${f['etiqueta']}'.startsWith('Comprobante de pago') && costo > 0 ? ' — monto: ${pesos(costo)}' : ''}'
                    '${f['rechazado'] == true ? ' — se rechazó${'${f['observacion'] ?? ''}'.isNotEmpty ? ': ${f['observacion']}' : ''}. Vuelve a subirlo.' : ''}',
                    style: TextStyle(fontSize: 13, height: 1.35, fontWeight: f['rechazado'] == true ? FontWeight.w700 : FontWeight.w500),
                  ),
                ),
              ]),
            ),
        ],
        if (tuyo) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: cessumRed),
              onPressed: _abrirGestion,
              icon: const Icon(Icons.upload, size: 18),
              label: const Text('Subir ahora'),
            ),
          ),
        ],
      ]),
    );
  }

  // ---------------- (25-sep) MODALIDADES Y COSTOS ----------------
  // Descripciones del Reglamento Escolar Institucional: Art. 71 (maestría) y
  // Art. 72 (doctorado). Jurado y examen según la norma de _rutaDe. Los
  // precios vienen del Guardián para el programa y la generación del alumno.

  static const _modMaestria = [
    {
      'clave': 'excelencia',
      'nombre': 'Excelencia académica',
      'req': 'Promedio general de 9.5 o más, sin materias reprobadas y sin interrupciones en tus estudios.',
      'examen': false,
    },
    {
      'clave': 'tesis',
      'nombre': 'Tesis',
      'req': 'Elaboras una tesis y la defiendes en una disertación ante un jurado.',
      'examen': true,
      'mencion': true,
    },
    {
      'clave': 'produccion',
      'nombre': 'Producción académica',
      'req': 'Dos publicaciones (artículos en revistas, libros o capítulos de libro) y la participación en un congreso arbitrado.',
      'examen': true,
    },
    {
      'clave': 'creditos',
      'nombre': 'Créditos de nivel superior',
      'req': 'Acreditar el primer y el segundo ciclos de un doctorado cursado en CESSUM.',
      'examen': false,
    },
  ];

  static const _modDoctorado = [
    {
      'clave': 'tesis',
      'nombre': 'Tesis',
      'req': 'Elaboras una tesis doctoral y la defiendes en una disertación ante un jurado.',
      'examen': true,
      'mencion': true,
    },
    {
      'clave': 'produccion',
      'nombre': 'Producción académica',
      'req': 'Dos publicaciones (artículos en revistas, libros o capítulos de libro) y la participación en dos congresos arbitrados.',
      'examen': true,
    },
    {
      'clave': 'estancia',
      'nombre': 'Estancia postdoctoral',
      'req': 'Estancia posdoctoral en CESSUM. No lleva examen: se dictamina el expediente.',
      'examen': false,
    },
  ];

  /// 'maestria' | 'doctorado' | '' (sin tabla de titulación, p. ej. licenciatura).
  String get _nivelTitulacion {
    final n = '${_precios?['nivel'] ?? ''}';
    if (n == 'maestria' || n == 'doctorado') return n;
    final prog = '${_perfil?.programa ?? ''}'.toLowerCase();
    if (prog.contains('doctorado')) return 'doctorado';
    if (prog.contains('maestr')) return 'maestria';
    return '';
  }

  String _pesosMod(num n) {
    final t = n.round().toString();
    final b = StringBuffer();
    for (var i = 0; i < t.length; i++) {
      if (i > 0 && (t.length - i) % 3 == 0) b.write(',');
      b.write(t[i]);
    }
    return '\$$b';
  }

  String _precioDe(String clave) {
    final ops = _precios?['opciones'];
    final v = ops is Map ? ops[clave] : null;
    final n = v is num ? v : num.tryParse('${v ?? ''}');
    if (n != null && n > 0) return _pesosMod(n);
    final mn = _precios?['min'], mx = _precios?['max'];
    if (mn is num && mx is num && mn > 0) return 'Entre ${_pesosMod(mn)} y ${_pesosMod(mx)}';
    return 'Por confirmar';
  }

  Widget _apartadoModalidades() {
    final lista = _nivelTitulacion == 'doctorado' ? _modDoctorado : _modMaestria;
    final miOpcion = _opcion.toLowerCase();
    final excelenciaNo = _eleg?['excelenciaDisponible'] == false;
    final rango = _precios != null &&
        (_precios!['opciones'] is! Map || (_precios!['opciones'] as Map).isEmpty);
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cessumGold.withValues(alpha: 0.45)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: _exp == null,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          leading: const Icon(Icons.school_outlined, color: cessumGold),
          title: const Text('Modalidades de titulación y costos',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          subtitle: Text(
            'Qué pide cada opción, si lleva examen y cuánto cuesta para tu programa y generación.',
            style: TextStyle(fontSize: 12, color: cessumMuted(context)),
          ),
          children: [
            for (final m in lista)
              _modalidad(
                m,
                esMia: miOpcion.isNotEmpty &&
                    miOpcion.contains('${m['nombre']}'.toLowerCase().split(' ').first),
                noDisponible: m['clave'] == 'excelencia' && excelenciaNo,
              ),
            if (rango)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  'El costo de cada opción de doctorado se confirma con Control Escolar al solicitar tu titulación.',
                  style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: cessumMuted(context)),
                ),
              ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cessumGold.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Para todas las opciones', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                for (final t in const [
                  'Haber concluido tus créditos y no tener adeudos con CESSUM (Art. 67).',
                  'La cuota de titulación se cubre en su totalidad; en las opciones con examen, antes del examen (Art. 77).',
                  'Tu expediente pasa por dos ventanillas ante la SEC: autenticación y certificación. Estos trámites toman más tiempo.',
                  'El Reglamento establece un plazo de cinco años para titularte (Art. 90).',
                  'Opcional: impresión de tus fotografías para el título en CESSUM, \$500.',
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('•  ', style: TextStyle(fontSize: 12.5)),
                      Expanded(child: Text(t, style: const TextStyle(fontSize: 12.5, height: 1.4))),
                    ]),
                  ),
              ]),
            ),
            const SizedBox(height: 8),
            Text(
              'Costos para tu programa y generación. Fuente: Reglamento Escolar Institucional, arts. 67, '
              '${_nivelTitulacion == 'doctorado' ? '72' : '71'}, 77, 85 y 90. Dudas: contacto@cessum.mx.',
              style: TextStyle(fontSize: 11, color: cessumMuted(context)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _modalidad(Map<String, Object> m, {bool esMia = false, bool noDisponible = false}) {
    final examen = m['examen'] == true;
    final Color borde = esMia ? cessumRed : (noDisponible ? Colors.grey : cessumMuted(context).withValues(alpha: 0.3));
    Widget chip(String t, Color c) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: c.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
          child: Text(t, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c)),
        );
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borde, width: esMia ? 1.6 : 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Text('${m['nombre']}',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: noDisponible ? Colors.grey : null)),
          ),
          const SizedBox(width: 8),
          Text(_precioDe('${m['clave']}'),
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: noDisponible ? Colors.grey : cessumRed)),
        ]),
        const SizedBox(height: 4),
        Text('${m['req']}', style: TextStyle(fontSize: 12.8, height: 1.4, color: noDisponible ? Colors.grey : null)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 4, children: [
          if (esMia) chip('Tu opción', cessumRed),
          examen ? chip('Con jurado y examen', cessumGold) : chip('Sin examen', const Color(0xFF1E7F52)),
          if (m['mencion'] == true) chip('Mención honorífica posible (promedio ≥ 9.0)', const Color(0xFF1E7F52)),
        ]),
        if (noDisponible)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'No disponible para ti${'${_eleg?['motivo'] ?? ''}'.isNotEmpty ? ': ${_eleg!['motivo']}' : '.'}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cessumRed),
            ),
          ),
      ]),
    );
  }

  Widget _botonPrincipal() {
    final etiqueta = _exp == null
        ? 'INICIAR MI TITULACIÓN'
        : (_etapaRechazada
            ? 'INICIAR UNA NUEVA SOLICITUD'
            : 'INICIAR MI EXPEDIENTE DE TITULACIÓN');
    final ayuda = _exp == null
        ? 'Elige tu opción de obtención de grado y envía tu solicitud.'
        : (_etapaRechazada
            ? 'Tu solicitud anterior no procedió. Aquí puedes presentar una nueva.'
            : 'Sube tus documentos y tu comprobante de pago.');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16)),
            icon: const Icon(Icons.assignment),
            label: Text(
              etiqueta,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3),
            ),
            onPressed: _abrirGestion,
          ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(ayuda,
              style: const TextStyle(fontSize: 12.5, height: 1.35)),
        ),
      ],
    );
  }

  // ---------------- encabezado ----------------

  Widget _encabezado(int total, int hechos) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [cessumRed, Color(0xFF8E1622)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Proceso de titulación',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 4),
          Text('$hechos de $total pasos completados',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900)),
          if (_opcion.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.workspace_premium,
                      size: 15, color: Colors.white),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text('Opción: $_opcion',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : hechos / total,
              minHeight: 8,
              backgroundColor: Colors.white24,
              valueColor: const AlwaysStoppedAnimation<Color>(cessumGold),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- entrega del TÍTULO + confirmación de recepción ----------
  /// Botón para que el alumno solicite recibir su título por ENVÍO. Aparece
  /// cuando el título ya está listo (Titulado o Entrega) y el alumno aún no ha
  /// solicitado el envío ni confirmado recepción. Si ya lo solicitó, muestra el
  /// estado en su lugar.
  // (ago-3) El alumno sube su comprobante de pago del servicio de paquetería.
  Future<void> _subirPagoPaqueteria() async {
    final doc = await seleccionarDocumento(tipo: 'ambos');
    if (doc == null || !mounted) return;
    try {
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'tit_envio_pago_subir',
                'folio': _s('folio'),
                'base64': base64Encode(doc.bytes),
                'mime': doc.mime,
              }))
          .timeout(const Duration(seconds: 120));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.green,
          content: Text('${data['mensaje'] ?? 'Comprobante recibido.'}')));
      _cargar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: cessumRed,
          content: Text('No se pudo subir: $e')));
    }
  }

  Widget _botonRecibirPorEnvio() {
    final etapa = _s('etapa');
    final listo = etapa == 'Titulado' || etapa == 'Entrega de título';
    if (!listo) return const SizedBox.shrink();
    // Ya confirmó recepción: no ofrecer envío.
    if (_s('tituloConfirmadoAlumno').toUpperCase() == 'SI') {
      return const SizedBox.shrink();
    }
    final yaSolicito = _s('envioConsentimiento').toUpperCase() == 'SI';
    if (yaSolicito) {
      final pagoSubido = _s('envioPagoUrl').isNotEmpty;
      // (ago-5) Rastreo visual del envío: el alumno ve en qué punto exacto
      // va su título sin preguntar. Los hitos salen de los campos reales
      // del expediente; el "actual" es el primer no-hecho.
      final guiaLista = _s('envioGuiaArchivoUrl').isNotEmpty ||
          _s('tituloGuiaUrl').isNotEmpty;
      final recolectado = _s('envioRecogidoEn').isNotEmpty;
      final entregado =
          _s('tituloConfirmadoAlumno').toUpperCase() == 'SI';
      final hechosEnv = [true, pagoSubido, guiaLista, recolectado, entregado];
      final primerPend = hechosEnv.indexOf(false);
      final hitosEnvio = <Map<String, dynamic>>[
        {
          'titulo': 'Solicitud de envío recibida',
          'hecho': true,
          'actual': false,
        },
        {
          'titulo': 'Comprobante de paquetería',
          'fecha': _s('envioPagoFecha'),
          'hecho': pagoSubido,
          'actual': primerPend == 1,
        },
        {
          'titulo': 'Guía de paquetería emitida',
          'hecho': guiaLista,
          'actual': primerPend == 2,
        },
        {
          'titulo': 'Recolectado — en camino',
          'fecha': _s('envioRecogidoEn'),
          'hecho': recolectado,
          'actual': primerPend == 3,
        },
        {
          'titulo': 'Entregado y confirmado por ti',
          'fecha': _s('tituloConfirmadoFecha'),
          'hecho': entregado,
          'actual': primerPend == 4,
        },
      ];
      final tarjetaRastreo = Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: cessumRed.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('📦 RASTREO DE TU ENVÍO',
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: cessumRed)),
            const SizedBox(height: 10),
            TimelineCessum(hitos: hitosEnvio),
          ],
        ),
      );
      final tarjetaPago = Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cessumGold.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cessumGold.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('💳 PAGO DEL SERVICIO DE PAQUETERÍA',
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF8A5A0F))),
            const SizedBox(height: 6),
            if (pagoSubido)
              Text(
                  '✓ Recibimos tu comprobante'
                  '${_s('envioPagoFecha').isNotEmpty ? ' el ${_s('envioPagoFecha')}' : ''}. '
                  'Con esto preparamos tu envío.',
                  style: const TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1B5E20)))
            else ...[
              // (ago-6) Importe: primero el fijado para ESTE envío por la
              // Vicerrectoría; si no hay, la tarifa general (propiedad).
              if (_s('envioCosto').isNotEmpty) ...[
                const Text('Importe total de tu envío:',
                    style: TextStyle(fontSize: 12, height: 1.4)),
                Text('\$${_s('envioCosto')} MXN',
                    style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: cessumRed)),
                const SizedBox(height: 4),
                const Text(
                    'Realiza tu pago y sube aquí tu comprobante:',
                    style: TextStyle(fontSize: 12, height: 1.4)),
              ] else
                Text(
                    'El envío por paquetería tiene un costo'
                    '${_s('envioPagoCosto').isNotEmpty ? ' de ${_s('envioPagoCosto')}' : ''} '
                    'que cubre el servicio de mensajería. Realiza tu pago y '
                    'sube aquí tu comprobante:',
                    style: const TextStyle(fontSize: 12, height: 1.4)),
              const SizedBox(height: 6),
              Text(_s('envioPagoDatos'),
                  style: const TextStyle(
                      fontSize: 11.5,
                      height: 1.5,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                      foregroundColor: cessumGold,
                      side: const BorderSide(color: cessumGold)),
                  onPressed: _subirPagoPaqueteria,
                  icon: const Icon(Icons.upload_file, size: 17),
                  label: const Text('Subir comprobante de pago'),
                ),
              ),
            ],
          ],
        ),
      );
      return Column(children: [
        tarjetaRastreo,
          tarjetaPago,
        Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF1E8E3E).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: const Color(0xFF1E8E3E).withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            const Icon(Icons.local_shipping,
                color: Color(0xFF1E8E3E), size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _s('envioRecogidoEn').isNotEmpty
                    ? '📦 Tu paquete fue recolectado por la paquetería el '
                        '${_s('envioRecogidoEn')}. ¡Tu título va en camino!'
                    : 'Ya solicitaste recibir tu título por envío. Te '
                        'avisaremos con el número de guía. Dirección '
                        'registrada:\n${_s('envioDireccion')}',
                style: const TextStyle(fontSize: 12, height: 1.4),
              ),
            ),
          ],
        ),
      ),
      ]);
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cessumRed.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cessumRed.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('¿No puedes recoger tu título en persona?',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
          const SizedBox(height: 6),
          Text(
            'Solicítalo por envío: captura tu dirección y te lo mandamos por '
            'paquetería con número de guía para rastrearlo.',
            style: TextStyle(
                fontSize: 12.5, color: cessumMuted(context), height: 1.4),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () async {
                final ok = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EnvioTituloScreen(
                      folio: _s('folio'),
                      matricula: _s('matricula'),
                      nombreAlumno: _perfil?.nombreCompleto ?? '',
                    ),
                  ),
                );
                if (ok == true) _cargar();
              },
              icon: const Icon(Icons.local_shipping),
              label: const Text('Recibir mi título por envío'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaEntregaTitulo() {    final modo = _s('tituloEntregaModo');
    final confirmado =
        _s('tituloConfirmadoAlumno').toUpperCase() == 'SI';
    final guia = _s('tituloGuiaUrl');
    final deslinde = _s('tituloDeslindeUrl');
    final paqueteria = _s('tituloPaqueteria');
    final fechaEst = _s('tituloFechaEstimada');

    if (confirmado) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF1E8E3E).withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: const Color(0xFF1E8E3E).withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            const Icon(Icons.verified, color: Color(0xFF1E8E3E)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Confirmaste la recepción de tu título el ${_s('tituloConfirmadoFecha')}. '
                '¡Felicidades y gracias por ser parte de CESSUM!',
                style: const TextStyle(fontSize: 12.5, height: 1.4),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cessumRed.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cessumRed.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.local_shipping, color: cessumRed, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Entrega de tu título',
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            modo == 'paqueteria'
                ? 'Tu título fue enviado por paquetería${paqueteria.isNotEmpty ? ' ($paqueteria)' : ''}.'
                    '${fechaEst.isNotEmpty ? ' Llegada estimada: $fechaEst.' : ''}'
                : 'Tu título está listo para entrega en físico. Coordina con Control Escolar.',
            style: const TextStyle(fontSize: 12.5, height: 1.4),
          ),
          if (guia.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => Helpers.abrirUrlExterna(guia, context),
                icon: const Icon(Icons.receipt_long,
                    size: 16, color: cessumGold),
                label: const Text('Ver la guía de rastreo',
                    style: TextStyle(color: cessumGold, fontSize: 12)),
              ),
            ),
          if (deslinde.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => Helpers.abrirUrlExterna(deslinde, context),
                icon: const Icon(Icons.description,
                    size: 16, color: cessumGold),
                label: const Text('Documento de recepción / deslinde',
                    style: TextStyle(color: cessumGold, fontSize: 12)),
              ),
            ),
          const Divider(height: 20),
          Text(
            'Cuando lo recibas, confirma la recepción. Esta confirmación tiene '
            'efectos de acuse de recibido.',
            style: TextStyle(fontSize: 12, color: cessumInk(context)),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: cessumRed,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 44),
            ),
            onPressed: _guardando ? null : _confirmarRecepcionTitulo,
            icon: const Icon(Icons.check_circle),
            label: const Text('Confirmar que recibí mi título'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmarRecepcionTitulo() async {
    bool acepta = false;
    final nombre =
        TextEditingController(text: _s('nombre'));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Confirmar recepción del título'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Al confirmar, declaras bajo protesta de decir verdad que '
                  'recibiste tu título profesional en buen estado. Esta '
                  'confirmación tiene efectos de acuse de recibido y deslinda a '
                  'la institución de entregas posteriores.',
                  style: TextStyle(fontSize: 12.5, height: 1.4),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nombre,
                  decoration: const InputDecoration(
                      labelText: 'Tu nombre completo (como acuse)'),
                ),
                const SizedBox(height: 4),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: acepta,
                  onChanged: (v) => setLocal(() => acepta = v ?? false),
                  title: const Text(
                    'Acepto y confirmo que recibí mi título.',
                    style: TextStyle(fontSize: 12.5),
                  ),
                ),
                Text(
                  'Opcional: si tienes un acuse firmado o foto del título '
                  'recibido, puedes subirlo luego desde el botón de arriba.',
                  style: TextStyle(fontSize: 11, color: cessumFaint(context)),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: cessumRed),
              onPressed: acepta && nombre.text.trim().isNotEmpty
                  ? () => Navigator.pop(ctx, true)
                  : null,
              child: const Text('Confirmar',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    setState(() => _guardando = true);
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'titulacion_entrega_confirmar',
        'folio': _s('folio'),
        'matricula': _s('matricula'),
        'acepta': '1',
        'nombre': nombre.text.trim(),
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: Colors.green,
          content: Text('¡Recepción confirmada! Te enviamos el acuse por correo.'),
        ));
        _cargar();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(data['error']?.toString() ?? 'No se pudo confirmar.'),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text('Error: $e'),
        ));
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  // ---------------- cronómetro de compromiso (72 h) ----------------

  Widget _tarjetaTimer() {
    // Si la pelota está en el ALUMNO (le faltan documentos o se los rechazaron),
    // el compromiso de 72 h está en pausa: no le decimos "estamos revisando",
    // le decimos claramente qué debe subir o corregir.
    if (_exp?['esperandoAlumno'] == true) {
      final faltantes = (_exp?['faltantes'] as List?) ?? [];
      final rechazados = (_exp?['rechazados'] as List?) ?? [];
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cessumGold.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cessumGold.withValues(alpha: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.assignment_late, color: cessumGold, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Faltan documentos de tu parte',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: cessumGold.withValues(alpha: 0.95)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Tu trámite avanza en cuanto subas o corrijas lo siguiente. '
              'Mientras tanto, el tiempo de revisión de la coordinación está en pausa.',
              style: TextStyle(
                  fontSize: 12.5, color: Colors.grey.shade800, height: 1.4),
            ),
            const SizedBox(height: 10),
            ...faltantes.map((f) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('•  ',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      Expanded(
                        child: Text(f.toString(),
                            style: const TextStyle(
                                fontSize: 12.5, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                )),
            if (rechazados.isNotEmpty) ...[
              const SizedBox(height: 6),
              ...rechazados.map((r) {
                final m = Map<String, dynamic>.from(r as Map);
                final obs = (m['observacion'] ?? '').toString();
                if (obs.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 4, left: 4),
                  child: Text(
                    '↳ ${m['etiqueta']}: $obs',
                    style: TextStyle(
                        fontSize: 11.5,
                        color: cessumRed,
                        fontStyle: FontStyle.italic),
                  ),
                );
              }),
            ],
          ],
        ),
      );
    }
    final horas = _horasParado;
    if (horas <= 0) return const SizedBox.shrink();
    final restan = _kHorasCompromiso - horas;
    final Color c;
    final IconData ic;
    final String titulo;
    final String detalle;
    if (restan <= 0) {
      c = cessumRed;
      ic = Icons.alarm;
      titulo = 'Tu trámite ya rebasó las $_kHorasCompromiso h';
      detalle =
          'Coordinación tiene tu expediente marcado como urgente. Si no ves '
          'avance pronto, comunícate con Control Escolar.';
    } else if (restan <= 24) {
      c = cessumGold;
      ic = Icons.timer_outlined;
      titulo = 'Revisión en curso · ${restan.round()} h restantes';
      detalle =
          'Nos comprometemos a resolver cada paso dentro de $_kHorasCompromiso '
          'horas. Ya casi.';
    } else {
      c = const Color(0xFF1E8E3E);
      ic = Icons.timer_outlined;
      titulo = 'Revisión en curso · ${restan.round()} h restantes';
      detalle =
          'Nos comprometemos a resolver cada paso dentro de $_kHorasCompromiso '
          'horas.';
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(ic, color: c, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo,
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: c)),
                const SizedBox(height: 3),
                Text(detalle,
                    style: const TextStyle(fontSize: 12, height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- tarjeta grande de ENTREGA DEL TITULO ----------------

  Widget _tarjetaEntrega() {
    final fecha = _s('entregaFecha');
    final hora = _s('entregaHora');
    final lugar = _s('entregaLugar');
    final nombre = (_perfil?.nombreCompleto ?? '').trim();
    final saludo =
        nombre.isEmpty ? '¡Felicidades!' : '¡Felicidades, ${_primerNombre(nombre)}!';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFB8842C), Color(0xFF8A6316)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.celebration, color: Colors.white, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Text(saludo,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text('ENTREGA DE TU TÍTULO',
              style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(fecha,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  height: 1.1,
                  fontWeight: FontWeight.w900)),
          if (hora.isNotEmpty || lugar.isNotEmpty) ...[
            const SizedBox(height: 10),
            if (hora.isNotEmpty)
              _lineaEntrega(Icons.schedule, hora),
            if (lugar.isNotEmpty) _lineaEntrega(Icons.place, lugar),
          ],
          const SizedBox(height: 12),
          const Text(
            'Presenta una identificación oficial el día de la entrega. '
            'Si no puedes asistir, avisa a Control Escolar.',
            style: TextStyle(color: Colors.white, fontSize: 12, height: 1.35),
          ),
          _tarjetaTiempoTramite(),
        ],
      ),
    );
  }

  /// Muestra cuánto tomó el trámite de la solicitud a la entrega del título.
  /// Es nuestro sello de servicio: pensado para que el alumno lo capture y
  /// comparta. Solo aparece si tenemos las dos fechas.
  Widget _tarjetaTiempoTramite() {
    final solMs = (_exp?['solicitudMs'] ?? 0);
    final entMs = (_exp?['entregaFechaMs'] ?? 0);
    final sol = (solMs is num && solMs > 0)
        ? DateTime.fromMillisecondsSinceEpoch(solMs.toInt())
        : null;
    final ent = (entMs is num && entMs > 0)
        ? DateTime.fromMillisecondsSinceEpoch(entMs.toInt())
        : null;
    if (sol == null || ent == null) return const SizedBox.shrink();
    final dias = ent.difference(sol).inDays;
    if (dias < 0) return const SizedBox.shrink();
    // Frase natural según la magnitud.
    String magnitud;
    if (dias == 0) {
      magnitud = 'el mismo día';
    } else if (dias == 1) {
      magnitud = 'en 1 día';
    } else if (dias < 31) {
      magnitud = 'en $dias días';
    } else {
      final meses = (dias / 30).floor();
      magnitud = meses <= 1 ? 'en poco más de un mes' : 'en unos $meses meses';
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(Icons.verified, color: Colors.white, size: 22),
          const SizedBox(height: 6),
          Text(
            'De tu solicitud a tu título',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 11.5,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            dias == 0 ? 'El mismo día' : '$dias días',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 30,
                height: 1.1,
                fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            'En CESSUM completamos tu titulación $magnitud. '
            'Gracias por confiar en nosotros. 🎓',
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white, fontSize: 12.5, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _lineaEntrega(IconData ic, String texto) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(ic, size: 16, color: Colors.white70),
          const SizedBox(width: 8),
          Expanded(
            child: Text(texto,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  String _primerNombre(String completo) {
    final partes = completo.trim().split(RegExp(r'\s+'));
    return partes.isEmpty ? completo : partes.first;
  }

  // ---------------- avisos ----------------

  /// Adelantar documentos antes de solicitar: el único momento en que la
  /// pantalla del expediente aporta algo. Al crear la solicitud, el Guardián
  /// copia lo cargado aquí a la hoja de Titulación.
  Widget _botonAdelantarExpediente() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: cessumRed,
          side: const BorderSide(color: cessumRed),
          padding: const EdgeInsets.symmetric(vertical: 13),
          minimumSize: const Size(double.infinity, 0),
        ),
        icon: const Icon(Icons.folder_copy, size: 19),
        label: Text(
            _exp == null
                ? 'Adelantar mis documentos'
                // (30-sep, Fase 1) Antes decía lo mismo que el botón
                // principal de arriba ("ver y subir documentos"), que
                // además ya lleva a todo el flujo (pago y fotos incluidos).
                // Este es el atajo para consultar el estado y corregir un
                // documento puntual sin entrar al flujo completo.
                : 'Ver mi expediente y corregir documentos',
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
        onPressed: () async {
          final p = await StudentProfile.load();
          if (!mounted) return;
          if (p == null) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Completa tu perfil para tu expediente')));
            return;
          }
          await Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => MiExpedienteTitulacionScreen(perfil: p)),
          );
          if (mounted) _cargar();
        },
      ),
    );
  }

  Widget _avisoSinSolicitud() {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cessumGold.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Text(
        'Aún no inicias tu solicitud de titulación. Cuando cumplas tus '
        'materias, puedes iniciarla desde el botón de abajo. Al iniciarla '
        'eliges tu OPCIÓN DE TITULACIÓN, y los pasos de esta pantalla se '
        'ajustan a la opción que elijas.',
        style: TextStyle(fontSize: 12.5),
      ),
    );
  }

  Widget _avisoSinExamen() {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E8E3E).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 18, color: Color(0xFF1E8E3E)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Tu opción de titulación ($_opcion) NO requiere designación de '
              'jurado ni examen profesional. Tu proceso se resuelve por '
              'dictamen de tu expediente.',
              style: const TextStyle(fontSize: 12.5, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  Widget _avisoExcepcion() {
    final rechazada = _etapaRechazada;
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cessumRed.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cessumRed.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.report_problem_outlined, size: 18, color: cessumRed),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              rechazada
                  ? 'Tu solicitud fue RECHAZADA. Acude a Control Escolar para '
                      'conocer el motivo y los pasos a seguir.'
                  : 'Tu examen quedó SUSPENDIDO. Control Escolar te contactará '
                      'para reprogramarlo.',
              style: const TextStyle(fontSize: 12.5, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- construccion de la ruta ----------------

  List<Map<String, dynamic>> _construirPasos() {
    final exp = _exp;
    final malla = _malla;
    final etapa = _s('etapa');
    final idx = _etapaIdx;
    final ruta = _ruta;
    final pasos = <Map<String, dynamic>>[];

    // ---- Paso: Requisitos academicos ----
    String e1;
    String d1;
    if (exp != null || (malla != null && malla['completa'] == true)) {
      e1 = 'done';
      d1 = 'Cumpliste los requisitos de materias.';
    } else if (malla != null && malla['conocido'] == true) {
      e1 = 'current';
      final faltan = malla['faltan'] ?? 0;
      d1 = 'Te faltan $faltan materias por acreditar para poder titularte.';
    } else {
      e1 = 'info';
      d1 = 'Verifica tu avance de materias en "Mi avance del plan".';
    }
    pasos.add({'titulo': 'Requisitos académicos', 'estado': e1, 'detalle': d1});

    // ---- Paso: Solicitud de titulacion ----
    String e2;
    String d2;
    if (exp == null) {
      e2 = 'pending';
      d2 = 'Inicia tu solicitud de titulación desde la app.';
    } else if (etapa == 'Solicitud en validación') {
      e2 = 'current';
      d2 = 'Tu solicitud está en revisión por la institución.';
    } else {
      e2 = 'done';
      d2 = 'Solicitud registrada'
          '${_opcion.isNotEmpty ? ' · Opción: $_opcion' : ''}.';
    }
    pasos.add(
        {'titulo': 'Solicitud de titulación', 'estado': e2, 'detalle': d2});

    // ---- Paso: Integracion de expediente ----
    String e3;
    String d3;
    if (exp == null) {
      e3 = 'pending';
      d3 = 'Sube tus documentos cuando inicies tu solicitud.';
    } else if (_docsCompletos) {
      e3 = 'done';
      d3 = 'Todos tus documentos fueron aprobados.';
    } else {
      e3 = 'current';
      final aprob =
          _docs.where((x) => (x['estatus'] ?? '') == 'Aprobado').length;
      d3 = 'Llevas $aprob de ${_docs.length} documentos aprobados.';
    }
    pasos.add({
      'titulo': 'Integración de expediente',
      'estado': e3,
      'detalle': d3,
      'docs': true
    });

    if (ruta.conJurado) {
      // ---- Paso: Designacion de jurado (solo rutas con examen) ----
      String e4;
      String d4;
      if (_sinodosListos) {
        e4 = 'done';
        d4 = 'Presidente, secretario y vocal designados.';
      } else if (exp != null && _docsCompletos) {
        e4 = 'current';
        d4 = 'Pendiente la designación de tu jurado.';
      } else {
        e4 = 'pending';
        d4 = 'Se designan al validar tu expediente.';
      }
      pasos.add(
          {'titulo': 'Designación de jurado', 'estado': e4, 'detalle': d4});
    }

    if (ruta.conExamen) {
      // ---- Paso: Examen profesional ----
      String e5;
      String d5;
      final resultado = _s('resultado');
      final exFecha = _s('examenFecha');
      if (resultado.isNotEmpty) {
        e5 = 'done';
        d5 = 'Resultado: $resultado.';
      } else if (_etapaSuspendida) {
        e5 = 'current';
        d5 = 'Examen suspendido. Se reprogramará.';
      } else if (exFecha.isNotEmpty) {
        e5 = 'current';
        final hora = _s('examenHora');
        final lugar = _s('examenLugar');
        d5 = 'Programado para el $exFecha'
            '${hora.isNotEmpty ? ' a las $hora' : ''}'
            '${lugar.isNotEmpty ? ' · $lugar' : ''}.';
      } else {
        e5 = 'pending';
        d5 = 'Se agenda tras la designación del jurado.';
      }
      pasos.add({
        'titulo': _esTesis ? 'Examen profesional' : 'Examen de réplica',
        'estado': e5,
        'detalle': d5,
        'acta': true
      });
    } else {
      // ---- Paso: Dictamen (rutas sin examen) ----
      String e4;
      String d4;
      if (idx >= _iExpedienteAprobado) {
        e4 = 'done';
        d4 = 'Tu expediente fue aprobado. Procede la emisión de tu título.';
      } else if (exp != null && _docsCompletos) {
        e4 = 'current';
        d4 = 'Tu expediente está en dictamen por la institución.';
      } else {
        e4 = 'pending';
        d4 = 'Se dictamina al completar tu expediente.';
      }
      pasos.add({
        'titulo': 'Dictamen de titulación',
        'estado': e4,
        'detalle': d4,
        'acta': true
      });
    }

    // ---- Paso: Ventanilla 1 (aplica a TODAS las opciones) ----
    String e6;
    String d6;
    if (idx >= _iVentanilla2) {
      e6 = 'done';
      d6 = 'Autenticación concluida.';
    } else if (idx == _iVentanilla1) {
      e6 = 'current';
      d6 = 'Tus documentos están en autenticación ante la autoridad educativa.';
    } else {
      e6 = 'pending';
      d6 = 'Inicia cuando se emita tu acta de titulación.';
    }
    pasos.add({
      'titulo': 'Ventanilla 1 · Autenticación',
      'estado': e6,
      'detalle': d6
    });

    // ---- Paso: Ventanilla 2 (aplica a TODAS las opciones) ----
    String e7;
    String d7;
    if (idx >= _iTitulado) {
      e7 = 'done';
      d7 = 'Certificación concluida.';
    } else if (idx == _iVentanilla2) {
      e7 = 'current';
      d7 = 'Tu título está en certificación ante la autoridad educativa.';
    } else {
      e7 = 'pending';
      d7 = 'Sigue a la autenticación de ventanilla 1.';
    }
    pasos.add({
      'titulo': 'Ventanilla 2 · Certificación',
      'estado': e7,
      'detalle': d7
    });

    // ---- Paso: Entrega del titulo ----
    String e8;
    String d8;
    if (_hayEntrega) {
      e8 = idx >= _iTitulado ? 'done' : 'current';
      final hora = _s('entregaHora');
      final lugar = _s('entregaLugar');
      final fechaEnt = _s('entregaFecha');
      d8 = 'Entrega el $fechaEnt'
          '${hora.isNotEmpty ? ' a las $hora' : ''}'
          '${lugar.isNotEmpty ? ' · $lugar' : ''}.';
    } else if (idx >= _iVentanilla1) {
      e8 = 'current';
      d8 = 'Te avisaremos la fecha de entrega en cuanto quede programada.';
    } else {
      e8 = 'pending';
      d8 = 'Se programa al concluir las ventanillas.';
    }
    pasos.add({
      'titulo': 'Entrega de tu título',
      'estado': e8,
      'detalle': d8,
    });

    return pasos;
  }

  // ---------------- tarjetas de paso ----------------

  Widget _tarjetaPaso(int n, Map<String, dynamic> paso) {
    final estado = paso['estado'] as String;
    final color = estado == 'done'
        ? const Color(0xFF1E8E3E)
        : estado == 'current'
            ? cessumRed
            : (estado == 'info' ? cessumGold : cessumFaint(context));
    final icono = estado == 'done'
        ? Icons.check
        : estado == 'current'
            ? Icons.play_arrow
            : (estado == 'info' ? Icons.info_outline : Icons.lock_outline);
    final etiqueta = estado == 'done'
        ? 'Completado'
        : estado == 'current'
            ? 'En proceso'
            : (estado == 'info' ? 'Revisa' : 'Pendiente');

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: color.withValues(alpha: 0.15),
                  child: Icon(icono, size: 18, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Paso $n · ${paso['titulo']}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 2),
                      Text(paso['detalle'].toString(),
                          style: TextStyle(
                              fontSize: 12.5, color: cessumInk(context))),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(etiqueta,
                      style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: color)),
                ),
              ],
            ),
            if (paso['docs'] == true && _docs.isNotEmpty) _checklistDocs(),
            if (paso['acta'] == true && _s('actaPdf').isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.download, size: 18),
                  label: const Text('Descargar acta'),
                  onPressed: () =>
                      Helpers.abrirUrlExterna(_s('actaPdf'), context),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _checklistDocs() {
    return Padding(
      padding: const EdgeInsets.only(top: 8, left: 44),
      child: Column(
        children: _docs.map((d) {
          final est = (d['estatus'] ?? '').toString();
          IconData ic;
          Color col;
          if (est == 'Aprobado') {
            ic = Icons.check_circle;
            col = const Color(0xFF1E8E3E);
          } else if (est == 'Rechazado') {
            ic = Icons.cancel;
            col = cessumRed;
          } else if (est.isNotEmpty) {
            ic = Icons.schedule;
            col = cessumGold;
          } else {
            ic = Icons.radio_button_unchecked;
            col = cessumFaint(context);
          }
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Icon(ic, size: 15, color: col),
                const SizedBox(width: 8),
                Expanded(
                  child: Text((d['etiqueta'] ?? '').toString(),
                      style: const TextStyle(fontSize: 12)),
                ),
                Text(est.isEmpty ? 'Falta' : est,
                    style: TextStyle(
                        fontSize: 11, color: col, fontWeight: FontWeight.w600)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

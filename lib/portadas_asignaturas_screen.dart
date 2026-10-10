import 'dart:convert';
import 'dart:ui' as ui;
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'helpers.dart';
import 'auth/session_store.dart';

/// Apartado del profesor: genera y descarga la PORTADA (2000x2000) de una
/// asignatura, sobre la plantilla oficial de cada programa. Mismo mecanismo
/// que "Banners semanales": se dibuja dentro de un RepaintBoundary a tamaño
/// nativo (2000x2000), se exporta a PNG y se descarga con dart:html.
///
/// (ago-17) DOS MODOS:
///   1. "Mis materias" (por omisión) — lee las asignaciones ACTIVAS del
///      docente con accion=mis_grupos (Code.gs → misGrupos(correo): solo
///      Activa=SI y sin invitación rechazada). El programa de la asignación
///      elige la plantilla automáticamente; si no se reconoce, se pide.
///   2. "Otra (catálogo)" — el camino anterior: Programa → Materia del plan,
///      más un campo de texto libre.
/// Ambos selectores abren un buscador (nada de listas planas largas).
///
/// Incluye el tutorial de cómo colocarla en Moodle (Archivos del resumen del
/// curso) con las dos advertencias: que reemplaza a la anterior y que el
/// banner de semana NO va ahí, sino como Etiqueta dentro del curso.
class PortadasAsignaturasScreen extends StatefulWidget {
  const PortadasAsignaturasScreen({super.key});

  @override
  State<PortadasAsignaturasScreen> createState() =>
      _PortadasAsignaturasScreenState();
}

enum _Modo { mis, catalogo }

class _PortadasAsignaturasScreenState extends State<PortadasAsignaturasScreen> {
  // ---------- Modo ----------
  _Modo _modo = _Modo.mis;

  // ---------- Mis materias (asignaciones activas) ----------
  List<Map<String, dynamic>> _materias = [];
  int? _idx; // índice dentro de _materias
  String _filtro = 'Vigentes'; // Vigentes | Todas
  bool _cargando = true;
  String? _error;

  /// Plantilla elegida a mano cuando el programa de la asignación no se
  /// reconoce (o cuando el docente quiere otra a propósito).
  int? _plantillaManual;

  /// Nombre editado a mano para la materia tomada de la asignación.
  String? _nombreMisOverride;

  // ---------- Catálogo ----------
  int _prog = 0; // índice de programa
  int? _mat; // índice de materia del plan (null si se usa "Otra")
  final TextEditingController _otra = TextEditingController();

  final GlobalKey _boundaryKey = GlobalKey();
  bool _precargado = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_precargado) {
      _precargado = true;
      for (final p in _kProgramas) {
        precacheImage(AssetImage(p.asset), context).catchError((_) {});
      }
    }
  }

  @override
  void dispose() {
    _otra.dispose();
    super.dispose();
  }

  // =====================================================================
  //  CARGA — asignaciones activas del docente (accion=mis_grupos)
  // =====================================================================
  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final correo = (await SessionStore.validEmail()) ?? '';
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'mis_grupos',
        'correo': correo,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      final lista = ((data['grupos'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      // Vigentes primero, luego próximas, luego terminadas; dentro de cada
      // bloque por fecha de término ascendente.
      lista.sort((a, b) {
        final ca = _estadoMateria(a), cb = _estadoMateria(b);
        if (ca != cb) return ca.compareTo(cb);
        final fa = _fecha((a['termino'] ?? '').toString()) ?? DateTime(2100);
        final fb = _fecha((b['termino'] ?? '').toString()) ?? DateTime(2100);
        return fa.compareTo(fb);
      });
      if (!mounted) return;
      setState(() {
        _materias = lista;
        int sel = lista.indexWhere((m) => _estadoMateria(m) == 0);
        if (sel < 0 && lista.isNotEmpty) sel = 0;
        _idx = sel >= 0 ? sel : null;
        _plantillaManual = null;
        _nombreMisOverride = null;
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudieron cargar tus materias. Revisa tu conexión.';
      });
    }
  }

  // =====================================================================
  //  SELECCIÓN EFECTIVA
  // =====================================================================
  Map<String, dynamic>? get _asig =>
      (_idx != null && _idx! >= 0 && _idx! < _materias.length)
          ? _materias[_idx!]
          : null;

  /// Índice de plantilla deducido del programa de la asignación (null si el
  /// nombre del programa no corresponde a ninguna plantilla existente).
  int? get _plantillaAuto {
    final a = _asig;
    if (a == null) return null;
    return _indexPrograma((a['programa'] ?? '').toString());
  }

  /// Plantilla que se va a usar. NULL = todavía no hay una decidida; en ese
  /// caso NO se dibuja nada (mejor pedirla que estampar la equivocada).
  int? get _progSel {
    if (_modo == _Modo.catalogo) return _prog;
    if (_asig == null) return null;
    return _plantillaManual ?? _plantillaAuto;
  }

  String get _nombreAsignatura {
    if (_modo == _Modo.mis) {
      final ov = (_nombreMisOverride ?? '').trim();
      if (ov.isNotEmpty) return ov;
      return (_asig?['materia'] ?? '').toString().trim();
    }
    final libre = _otra.text.trim();
    if (libre.isNotEmpty) return libre;
    final p = _kProgramas[_prog];
    if (_mat != null && _mat! >= 0 && _mat! < p.materias.length) {
      return p.materias[_mat!];
    }
    return '';
  }

  bool get _listoParaGenerar =>
      _progSel != null && _nombreAsignatura.isNotEmpty;

  // =====================================================================
  //  NORMALIZACIÓN Y MAPEO PROGRAMA → PLANTILLA
  // =====================================================================
  static String _norm(String s) {
    var t = s.toLowerCase().trim();
    const acentos = {
      'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u', 'ñ': 'n',
      'à': 'a', 'è': 'e', 'ì': 'i', 'ò': 'o', 'ù': 'u',
    };
    acentos.forEach((k, v) => t = t.replaceAll(k, v));
    t = t.replaceAll(RegExp(r'[^a-z0-9 ]+'), ' ');
    return t.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// El texto de la columna Programa en Base Asignaciones no siempre viene
  /// idéntico al nombre de la plantilla (acentos, "Educacion", sufijos). Se
  /// resuelve primero por igualdad exacta normalizada y luego por palabras
  /// clave, en orden: lo más específico primero.
  static int? _indexPrograma(String programa) {
    final n = _norm(programa);
    if (n.isEmpty) return null;
    for (int i = 0; i < _kProgramas.length; i++) {
      if (_norm(_kProgramas[i].nombre) == n) return i;
    }
    final doctorado = n.contains('doctorado');
    if (doctorado) {
      if (n.contains('ciencias')) return _idxPorNombre('Doctorado en Ciencias');
      if (n.contains('investigacion') || n.contains('enfasis')) {
        return _idxPorNombre('Doctorado en Educación con');
      }
      return null; // doctorado que no reconozco: que lo elija el docente
    }
    if (n.contains('psicopedagog')) return _idxPorNombre('Psicopedagogía');
    if (n.contains('inclusiva')) return _idxPorNombre('Educación Inclusiva');
    if (n.contains('pedagog')) return _idxPorNombre('Maestría en Pedagogía');
    if (n.contains('educacion')) return _idxPorNombre('Maestría en Educación');
    return null;
  }

  static int? _idxPorNombre(String fragmento) {
    final f = _norm(fragmento);
    for (int i = 0; i < _kProgramas.length; i++) {
      if (_norm(_kProgramas[i].nombre).startsWith(f) ||
          _norm(_kProgramas[i].nombre).contains(f)) {
        return i;
      }
    }
    return null;
  }

  // Palabras que no distinguen una materia de otra.
  static const _vacias = {
    'de', 'del', 'la', 'las', 'el', 'los', 'y', 'e', 'en', 'a', 'al', 'para',
    'con', 'su', 'sus', 'un', 'una'
  };

  static double _parecido(String a, String b) {
    final ta = _norm(a).split(' ').where((w) => !_vacias.contains(w)).toSet();
    final tb = _norm(b).split(' ').where((w) => !_vacias.contains(w)).toSet();
    if (ta.isEmpty || tb.isEmpty) return 0;
    final comunes = ta.intersection(tb).length;
    return comunes / (ta.length > tb.length ? ta.length : tb.length);
  }

  /// Si la materia de la asignación se parece mucho a una del plan pero está
  /// escrita distinto, se sugiere la del plan (sin imponerla).
  String? _sugerenciaPlan() {
    if (_modo != _Modo.mis) return null;
    final prog = _progSel;
    if (prog == null) return null;
    final actual = _nombreAsignatura;
    if (actual.isEmpty) return null;
    final lista = _kProgramas[prog].materias;
    for (final m in lista) {
      if (_norm(m) == _norm(actual)) return null; // ya coincide
    }
    String? mejor;
    double punt = 0;
    for (final m in lista) {
      final p = _parecido(actual, m);
      if (p > punt) {
        punt = p;
        mejor = m;
      }
    }
    return punt >= 0.6 ? mejor : null;
  }

  /// Otros grupos donde el docente imparte la MISMA materia (bloque conjunto
  /// o dos grupos): la portada sirve para todos, conviene decirlo.
  List<String> _mismosGrupos() {
    final a = _asig;
    if (a == null) return const [];
    final n = _norm((a['materia'] ?? '').toString());
    final out = <String>[];
    for (int i = 0; i < _materias.length; i++) {
      if (i == _idx) continue;
      if (_norm((_materias[i]['materia'] ?? '').toString()) != n) continue;
      final g = (_materias[i]['grupo'] ?? '').toString().trim();
      if (g.isNotEmpty && !out.contains(g)) out.add(g);
    }
    return out;
  }

  // =====================================================================
  //  FECHAS Y ESTADO (mismo criterio que Banners semanales)
  // =====================================================================
  static const List<String> _meses = [
    'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
    'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'
  ];

  DateTime? _fecha(String s) {
    s = s.trim();
    if (s.isEmpty) return null;
    final m1 = RegExp(r'(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(s);
    if (m1 != null) {
      return DateTime(int.parse(m1.group(1)!), int.parse(m1.group(2)!),
          int.parse(m1.group(3)!));
    }
    final m2 = RegExp(r'(\d{1,2})/(\d{1,2})/(\d{4})').firstMatch(s);
    if (m2 != null) {
      return DateTime(int.parse(m2.group(3)!), int.parse(m2.group(2)!),
          int.parse(m2.group(1)!));
    }
    const mesEn = {
      'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
      'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12
    };
    final m3 =
        RegExp(r'([A-Za-z]{3})[a-z]*\s+(\d{1,2})\s+(\d{4})').firstMatch(s);
    if (m3 != null) {
      final mes = mesEn[m3.group(1)!.toLowerCase()];
      if (mes != null) {
        return DateTime(int.parse(m3.group(3)!), mes, int.parse(m3.group(2)!));
      }
    }
    return null;
  }

  /// 0 = vigente, 1 = próxima, 2 = terminada.
  int _estadoMateria(Map<String, dynamic> m) {
    final hoy = DateTime.now();
    final ini = _fecha((m['inicio'] ?? '').toString());
    final fin = _fecha((m['termino'] ?? '').toString());
    if (fin != null && hoy.isAfter(fin.add(const Duration(days: 1)))) return 2;
    if (ini != null && hoy.isBefore(ini)) return 1;
    if (ini != null || fin != null) return 0;
    return 1;
  }

  String _etiquetaEstado(int e) =>
      e == 0 ? 'Vigente' : (e == 1 ? 'Próxima' : 'Terminada');

  Color _colorEstado(int e) => e == 0
      ? const Color(0xFF1E8E3E)
      : (e == 1 ? cessumGold : Colors.grey);

  String _fechaLarga(DateTime d) =>
      '${d.day} de ${_meses[d.month - 1]} de ${d.year}';

  List<int> _indicesVisibles() {
    final out = <int>[];
    for (int i = 0; i < _materias.length; i++) {
      if (_filtro == 'Vigentes' && _estadoMateria(_materias[i]) != 0) continue;
      out.add(i);
    }
    return out;
  }

  // =====================================================================
  //  DESCARGA PNG (2000x2000)
  // =====================================================================
  String _slug(String s) {
    final t = s
        .replaceAll(RegExp(r'[^A-Za-z0-9 ]+'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '_');
    return t.isEmpty ? 'portada' : t;
  }

  Future<void> _descargar() async {
    if (_progSel == null) {
      _aviso('Falta elegir la plantilla del programa.');
      return;
    }
    if (_nombreAsignatura.isEmpty) {
      _aviso(_modo == _Modo.mis
          ? 'Elige una de tus materias.'
          : 'Elige una materia o escribe una en "Otra asignatura".');
      return;
    }
    try {
      final ctx = _boundaryKey.currentContext;
      if (ctx == null) return;
      final boundary = ctx.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      final blob = html.Blob([bytes.buffer.asUint8List()], 'image/png');
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)
        ..download = 'Portada_${_slug(_nombreAsignatura)}.png'
        ..click();
      html.Url.revokeObjectUrl(url);
    } catch (e) {
      if (!mounted) return;
      _aviso('No se pudo generar la imagen: $e');
    }
  }

  void _aviso(String txt) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(txt)));
  }

  // =====================================================================
  //  BUILD
  // =====================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Portadas de asignatura'),
        actions: [
          IconButton(
            tooltip: 'Recargar mis materias',
            icon: const Icon(Icons.refresh),
            onPressed: _cargando ? null : _cargar,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          Text(
            'Genera la portada oficial del curso (2000×2000) y súbela al Aula '
            'como imagen del resumen del curso.',
            style: CessumType.body(13, color: cessumMuted(context)),
          ),
          const SizedBox(height: 12),
          _chipsModo(),
          const SizedBox(height: 12),
          if (_modo == _Modo.mis) ..._bloqueMisMaterias(),
          if (_modo == _Modo.catalogo) ..._bloqueCatalogo(),
          ..._bloqueAvisos(),
          const SizedBox(height: 16),
          _vistaPrevia(),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _listoParaGenerar ? cessumRed : Colors.grey,
              ),
              onPressed: _listoParaGenerar ? _descargar : null,
              icon: const Icon(Icons.download, size: 18),
              label: const Text('Descargar portada'),
            ),
          ),
          const SizedBox(height: 18),
          _TutorialMoodle(
            linkAula: (_asig?['linkAula'] ?? '').toString().trim(),
          ),
        ],
      ),
    );
  }

  // ---------- Chips de modo ----------
  Widget _chipsModo() {
    Widget chip(_Modo m, String txt, IconData ic) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            avatar: Icon(ic,
                size: 15,
                color: _modo == m ? cessumRed : cessumMuted(context)),
            label: Text(txt),
            selected: _modo == m,
            selectedColor: cessumRed.withValues(alpha: 0.15),
            labelStyle: TextStyle(
              fontSize: 12,
              color: _modo == m ? cessumRed : cessumMuted(context),
              fontWeight: _modo == m ? FontWeight.w700 : FontWeight.w500,
            ),
            onSelected: (_) => setState(() => _modo = m),
          ),
        );
    return Row(children: [
      chip(_Modo.mis, 'Mis materias', Icons.assignment_ind_outlined),
      chip(_Modo.catalogo, 'Otra (catálogo)', Icons.menu_book_outlined),
    ]);
  }

  // ---------- Modo 1: mis asignaciones activas ----------
  List<Widget> _bloqueMisMaterias() {
    if (_cargando) {
      return const [SkeletonCard(), SizedBox(height: 12), SkeletonCard()];
    }
    if (_error != null) {
      return [
        _tarjeta(
          color: cessumRed,
          icono: Icons.wifi_off_rounded,
          titulo: 'No se pudo cargar',
          texto: _error!,
          accion: 'Reintentar',
          onAccion: _cargar,
        ),
      ];
    }
    if (_materias.isEmpty) {
      return [
        _tarjeta(
          color: cessumGold,
          icono: Icons.inbox_rounded,
          titulo: 'Sin asignaciones activas',
          texto: 'No tienes materias activas registradas a tu nombre. Puedes '
              'generar la portada desde el catálogo mientras se registra tu '
              'asignación.',
          accion: 'Usar el catálogo',
          onAccion: () => setState(() => _modo = _Modo.catalogo),
        ),
      ];
    }

    final vis = _indicesVisibles();
    final a = _asig;
    final estado = a != null ? _estadoMateria(a) : 1;
    final prog = _progSel;

    return [
      Row(
        children: [
          for (final op in const ['Vigentes', 'Todas'])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(op == 'Vigentes'
                    ? 'Vigentes (${_materias.where((m) => _estadoMateria(m) == 0).length})'
                    : 'Todas (${_materias.length})'),
                selected: _filtro == op,
                selectedColor: cessumRed.withValues(alpha: 0.15),
                labelStyle: TextStyle(
                  fontSize: 12,
                  color: _filtro == op ? cessumRed : cessumMuted(context),
                  fontWeight:
                      _filtro == op ? FontWeight.w700 : FontWeight.w500,
                ),
                onSelected: (_) => setState(() {
                  _filtro = op;
                  final v = _indicesVisibles();
                  if (!v.contains(_idx)) {
                    _idx = v.isNotEmpty ? v.first : null;
                    _plantillaManual = null;
                    _nombreMisOverride = null;
                  }
                }),
              ),
            ),
        ],
      ),
      const SizedBox(height: 12),
      _campoSelector(
        label: 'Mi asignatura',
        valor: a == null
            ? (vis.isEmpty ? 'No hay materias con este filtro' : 'Elige…')
            : '${a['materia'] ?? ''} · ${a['grupo'] ?? ''}',
        icono: Icons.school_outlined,
        trailing: a == null
            ? null
            : _chipEstado(estado),
        onTap: vis.isEmpty
            ? null
            : () async {
                final sel = await _elegir(
                  titulo: 'Elige tu asignatura',
                  hint: 'Filtra por materia, grupo, generación o clave…',
                  opciones: [
                    for (final i in vis)
                      _Opcion(
                        valor: i,
                        titulo: (_materias[i]['materia'] ?? '').toString(),
                        subtitulo: [
                          (_materias[i]['programa'] ?? '').toString(),
                          (_materias[i]['grupo'] ?? '').toString(),
                          (_materias[i]['generacion'] ?? '').toString(),
                          (_materias[i]['clave'] ?? '').toString(),
                        ].where((s) => s.trim().isNotEmpty).join(' · '),
                        etiqueta: _etiquetaEstado(_estadoMateria(_materias[i])),
                        etiquetaColor:
                            _colorEstado(_estadoMateria(_materias[i])),
                      ),
                  ],
                );
                if (sel == null) return;
                setState(() {
                  _idx = sel;
                  _plantillaManual = null;
                  _nombreMisOverride = null;
                });
              },
      ),
      if (a != null) ...[
        const SizedBox(height: 6),
        Text(_infoAsignacion(a),
            style: CessumType.label(12, color: cessumGold)),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Text(
                prog == null
                    ? 'Plantilla: sin definir'
                    : 'Plantilla: ${_kProgramas[prog].nombre}'
                        '${_plantillaManual != null ? ' (elegida a mano)' : ''}',
                style: CessumType.body(12, color: cessumMuted(context)),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton.icon(
              onPressed: _elegirPlantilla,
              icon: const Icon(Icons.palette_outlined, size: 16),
              label: const Text('Cambiar', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(foregroundColor: cessumRed),
            ),
            TextButton.icon(
              onPressed: _editarNombre,
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Nombre', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(foregroundColor: cessumRed),
            ),
          ],
        ),
      ],
    ];
  }

  String _infoAsignacion(Map<String, dynamic> a) {
    final ini = _fecha((a['inicio'] ?? '').toString());
    final fin = _fecha((a['termino'] ?? '').toString());
    final partes = <String>[];
    final tipo = (a['tipoSesiones'] ?? '').toString().trim();
    if (tipo.isNotEmpty) partes.add(tipo);
    final dia = (a['dia'] ?? '').toString().trim();
    final hora = (a['hora'] ?? '').toString().trim();
    if (dia.isNotEmpty || hora.isNotEmpty) {
      partes.add([dia, hora].where((s) => s.isNotEmpty).join(' '));
    }
    if (ini != null && fin != null) {
      partes.add('del ${_fechaLarga(ini)} al ${_fechaLarga(fin)}');
    } else if (ini != null) {
      partes.add('inicia el ${_fechaLarga(ini)}');
    } else {
      partes.add('sin fechas registradas');
    }
    return partes.join(' · ');
  }

  Widget _chipEstado(int e) {
    final color = _colorEstado(e);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        _etiquetaEstado(e),
        style:
            TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }

  // ---------- Modo 2: catálogo ----------
  List<Widget> _bloqueCatalogo() {
    final p = _kProgramas[_prog];
    return [
      _campoSelector(
        label: 'Programa',
        valor: p.nombre,
        icono: Icons.account_balance_outlined,
        onTap: () async {
          final sel = await _elegir(
            titulo: 'Elige el programa',
            hint: 'Filtra por nombre del programa…',
            opciones: [
              for (int i = 0; i < _kProgramas.length; i++)
                _Opcion(
                  valor: i,
                  titulo: _kProgramas[i].nombre,
                  subtitulo: '${_kProgramas[i].materias.length} materias',
                ),
            ],
          );
          if (sel == null) return;
          setState(() {
            _prog = sel;
            _mat = null;
          });
        },
      ),
      const SizedBox(height: 12),
      _campoSelector(
        label: 'Materia del plan',
        valor: (_mat != null && _mat! < p.materias.length)
            ? p.materias[_mat!]
            : 'Elige…',
        icono: Icons.menu_book_outlined,
        onTap: () async {
          final sel = await _elegir(
            titulo: 'Elige la materia',
            hint: 'Escribe parte del nombre…',
            opciones: [
              for (int i = 0; i < p.materias.length; i++)
                _Opcion(valor: i, titulo: p.materias[i]),
            ],
          );
          if (sel == null) return;
          setState(() {
            _mat = sel;
            _otra.clear();
          });
        },
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _otra,
        decoration: _dec('Otra asignatura (texto libre)').copyWith(
          hintText: 'Escríbela para generar una que no esté en el plan',
        ),
        onChanged: (_) => setState(() => _mat = null),
      ),
    ];
  }

  // ---------- Avisos asistidos ----------
  List<Widget> _bloqueAvisos() {
    final out = <Widget>[];
    final a = _asig;

    // 1. Plantilla no reconocida.
    if (_modo == _Modo.mis && a != null && _progSel == null) {
      out.add(_tarjeta(
        color: cessumGold,
        icono: Icons.help_outline,
        titulo: 'No reconozco la plantilla de este programa',
        texto: 'La asignación dice «${a['programa'] ?? '—'}» y no coincide con '
            'ninguna de las ${_kProgramas.length} plantillas cargadas. Elige '
            'cuál usar para no estampar la equivocada.',
        accion: 'Elegir plantilla',
        onAccion: _elegirPlantilla,
      ));
    }

    // 2. Materia ya terminada.
    if (_modo == _Modo.mis && a != null && _estadoMateria(a) == 2) {
      final fin = _fecha((a['termino'] ?? '').toString());
      out.add(_tarjeta(
        color: cessumFaint(context),
        icono: Icons.history,
        titulo: 'Esta materia ya terminó',
        texto: fin != null
            ? 'Terminó el ${_fechaLarga(fin)}. Si buscas la del periodo que '
                'viene, cambia el filtro a "Vigentes".'
            : 'Ya no está en curso según sus fechas.',
      ));
    }

    // 3. El nombre no coincide con el plan de estudios.
    final sug = _sugerenciaPlan();
    if (sug != null) {
      out.add(_tarjeta(
        color: cessumGold,
        icono: Icons.rule,
        titulo: 'En el plan aparece con otro nombre',
        texto: 'La asignación dice «$_nombreAsignatura», pero en el plan del '
            'programa la materia se llama «$sug». Conviene que la portada use '
            'el nombre del plan.',
        accion: 'Usar el del plan',
        onAccion: () => setState(() => _nombreMisOverride = sug),
      ));
    }

    // 4. Nombre muy largo: se está imprimiendo pequeño.
    if (_listoParaGenerar) {
      final prog = _kProgramas[_progSel!];
      final top = prog.labelBottom + 40.0;
      final fs = _fit(_nombreAsignatura, 1140, 1600 - top);
      if (fs < 70) {
        final tieneDosPuntos = _nombreAsignatura.contains(':');
        out.add(_tarjeta(
          color: cessumGold,
          icono: Icons.text_fields,
          titulo: 'El nombre queda pequeño',
          texto: 'Es largo, así que se ajustó a ${fs.round()} px para que '
              'quepa en la caja de la plantilla.'
              '${tieneDosPuntos ? ' Puedes cortar el subtítulo que va después de los dos puntos.' : ''}',
          accion: tieneDosPuntos ? 'Cortar el subtítulo' : null,
          onAccion: tieneDosPuntos
              ? () {
                  final corto =
                      _nombreAsignatura.split(':').first.trim();
                  setState(() {
                    if (_modo == _Modo.mis) {
                      _nombreMisOverride = corto;
                    } else {
                      _otra.text = corto;
                      _mat = null;
                    }
                  });
                }
              : null,
        ));
      }
    }

    // 5. La misma materia en otros grupos.
    final otros = _mismosGrupos();
    if (_modo == _Modo.mis && otros.isNotEmpty) {
      out.add(_tarjeta(
        color: const Color(0xFF1E8E3E),
        icono: Icons.copy_all_outlined,
        titulo: 'También la impartes en ${otros.length == 1 ? 'otro grupo' : 'otros grupos'}',
        texto: 'Grupo(s): ${otros.join(', ')}. La misma portada sirve para '
            'todos: súbela en cada curso del Aula.',
      ));
    }

    if (out.isEmpty) return const [];
    return [const SizedBox(height: 12), ...out];
  }

  Widget _tarjeta({
    required Color color,
    required IconData icono,
    required String titulo,
    required String texto,
    String? accion,
    VoidCallback? onAccion,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo,
                    style: CessumType.heading(13, color: cessumInk(context))),
                const SizedBox(height: 4),
                Text(texto,
                    style: CessumType.body(12, color: cessumMuted(context))),
                if (accion != null && onAccion != null) ...[
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: onAccion,
                      style: TextButton.styleFrom(
                        foregroundColor: color,
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 30),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(accion,
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------- Diálogos ----------
  Future<void> _elegirPlantilla() async {
    final sel = await _elegir(
      titulo: 'Plantilla del programa',
      hint: 'Filtra por nombre del programa…',
      opciones: [
        for (int i = 0; i < _kProgramas.length; i++)
          _Opcion(
            valor: i,
            titulo: _kProgramas[i].nombre,
            subtitulo: '${_kProgramas[i].materias.length} materias en el plan',
          ),
      ],
    );
    if (sel == null) return;
    setState(() {
      if (_modo == _Modo.mis) {
        _plantillaManual = sel;
      } else {
        _prog = sel;
        _mat = null;
      }
    });
  }

  Future<void> _editarNombre() async {
    final ctl = TextEditingController(text: _nombreAsignatura);
    final res = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Nombre en la portada',
            style: TextStyle(fontSize: 16)),
        content: SizedBox(
          width: 460,
          child: TextField(
            controller: ctl,
            autofocus: true,
            maxLines: 3,
            minLines: 1,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              helperText: 'Solo cambia lo que se estampa en la imagen.',
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(context, ctl.text.trim()),
            child: const Text('Aplicar'),
          ),
        ],
      ),
    );
    ctl.dispose();
    if (res == null) return;
    setState(() {
      if (_modo == _Modo.mis) {
        _nombreMisOverride = res.isEmpty ? null : res;
      } else {
        _otra.text = res;
        _mat = null;
      }
    });
  }

  Future<int?> _elegir({
    required String titulo,
    required String hint,
    required List<_Opcion> opciones,
  }) {
    return showDialog<int>(
      context: context,
      builder: (_) =>
          _PickerBuscable(titulo: titulo, hint: hint, opciones: opciones),
    );
  }

  // ---------- Campo tipo selector (abre el buscador) ----------
  Widget _campoSelector({
    required String label,
    required String valor,
    required IconData icono,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: InputDecorator(
        decoration: _dec(label).copyWith(
          prefixIcon: Icon(icono, size: 18, color: cessumMuted(context)),
          suffixIcon: const Icon(Icons.search, size: 18),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                valor,
                overflow: TextOverflow.ellipsis,
                style: CessumType.body(13, color: cessumInk(context)),
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 6), trailing],
          ],
        ),
      ),
    );
  }

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: cessumRed, width: 1.6),
        ),
      );

  // ---------- Vista previa ----------
  Widget _vistaPrevia() {
    if (!_listoParaGenerar) {
      return AspectRatio(
        aspectRatio: 1,
        child: Container(
          decoration: BoxDecoration(
            color: cessumGold.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cessumGold.withValues(alpha: 0.30)),
          ),
          alignment: Alignment.center,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.image_outlined, size: 48, color: cessumGold),
                const SizedBox(height: 10),
                Text(
                  _progSel == null && _modo == _Modo.mis && _asig != null
                      ? 'Elige la plantilla del programa para ver la portada'
                      : (_modo == _Modo.mis
                          ? 'Elige una de tus materias para ver la portada'
                          : 'Elige la materia o escribe una para ver la portada'),
                  textAlign: TextAlign.center,
                  style: CessumType.body(13, color: cessumMuted(context)),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(
        aspectRatio: 1,
        child: FittedBox(
          fit: BoxFit.contain,
          child: RepaintBoundary(
            key: _boundaryKey,
            child: SizedBox(
              width: 2000,
              height: 2000,
              child: _portada(_nombreAsignatura),
            ),
          ),
        ),
      ),
    );
  }

  // ---------- Auto-ajuste del tamaño de fuente ----------
  // Mayor tamaño con el que el nombre cabe en la caja (ancho fijo, alto tope).
  double _fit(String texto, double maxW, double maxH) {
    final palabras = texto.trim().split(RegExp(r'\s+'));
    for (double size = 210; size >= 30; size -= 2) {
      final style = GoogleFonts.montserrat(
        fontSize: size,
        fontWeight: FontWeight.w700,
        height: 1.12,
      );
      // La palabra más larga debe caber ENTERA (evita cortes a media palabra).
      var palabraCabe = true;
      for (final w in palabras) {
        final wp = TextPainter(
          text: TextSpan(text: w, style: style),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout();
        if (wp.width > maxW) {
          palabraCabe = false;
          break;
        }
      }
      if (!palabraCabe) continue;
      final tp = TextPainter(
        text: TextSpan(text: texto, style: style),
        textDirection: TextDirection.ltr,
        maxLines: 8,
      )..layout(maxWidth: maxW);
      if (!tp.didExceedMaxLines && tp.height <= maxH) return size;
    }
    return 30;
  }

  // ---------- La portada: plantilla del programa + nombre (Montserrat) ----------
  Widget _portada(String nombre) {
    final p = _kProgramas[_progSel ?? 0];
    const double x0 = 774;
    const double w = 1140;
    const double logoTop = 1600;
    final double top = p.labelBottom + 40.0;
    final double h = logoTop - top;
    final double fs = nombre.isEmpty ? 120 : _fit(nombre, w, h);
    return Container(
      color: Colors.white,
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              p.asset,
              fit: BoxFit.fill,
              errorBuilder: (_, __, ___) =>
                  Container(color: const Color(0xFF3A2A46)),
            ),
          ),
          Positioned(
            left: x0,
            top: top,
            width: w,
            height: h,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                nombre,
                textAlign: TextAlign.left,
                maxLines: 8,
                style: GoogleFonts.montserrat(
                  fontSize: fs,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  height: 1.12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
//  TUTORIAL: cómo colocar la portada en Moodle
// =====================================================================
class _TutorialMoodle extends StatelessWidget {
  final String linkAula;
  const _TutorialMoodle({this.linkAula = ''});

  static const List<List<String>> _pasos = [
    [
      'Entra a tu curso en el Aula',
      'Abre aula.cessum.mx, entra al curso y activa el interruptor '
          'Modo de edición (arriba a la derecha).'
    ],
    [
      'Abre Configuración',
      'En el menú del curso (Curso · Configuración · Participantes · '
          'Calificaciones), toca Configuración.'
    ],
    [
      'Baja a Archivos del resumen del curso',
      'Está dentro del bloque General, justo debajo del Resumen del curso.'
    ],
    [
      'Sube la imagen',
      'Arrastra el PNG que descargaste al recuadro, o usa el icono Agregar → '
          'Subir un archivo → Seleccionar archivo → Subir este archivo.'
    ],
    [
      'Guarda',
      'Hasta abajo, Guardar y mostrar. La portada queda como imagen del curso '
          'en el tablero del alumno.'
    ],
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cessumGold.withValues(alpha: 0.35)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          leading: const Icon(Icons.help_outline, color: cessumGold),
          title: Text('Cómo ponerla en Moodle',
              style: CessumType.heading(14, color: cessumInk(context))),
          subtitle: Text('5 pasos · Archivos del resumen del curso',
              style: CessumType.label(11, color: cessumMuted(context))),
          children: [
            for (int i = 0; i < _pasos.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                          color: cessumRed, shape: BoxShape.circle),
                      child: Text('${i + 1}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_pasos[i][0],
                              style: CessumType.heading(12.5,
                                  color: cessumInk(context))),
                          const SizedBox(height: 2),
                          Text(_pasos[i][1],
                              style: CessumType.body(12,
                                  color: cessumMuted(context))),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            _advertencia(
              context,
              Icons.warning_amber_rounded,
              'Reemplaza a la portada anterior',
              'Moodle permite guardar varias imágenes en ese campo, pero en la '
                  'tarjeta del curso muestra una sola. Antes de subir la nueva, '
                  'toca la anterior y elige Eliminar; si no, puede seguir '
                  'apareciendo la vieja.',
            ),
            _advertencia(
              context,
              Icons.info_outline,
              'El banner de semana NO va aquí',
              'La portada es la imagen del curso. El banner semanal va DENTRO '
                  'del curso: Añadir una actividad o recurso → Etiqueta, '
                  'colocada arriba del encuadre de esa semana.',
            ),
            if (linkAula.isNotEmpty) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: cessumRed,
                    side: const BorderSide(color: cessumRed),
                  ),
                  onPressed: () => Helpers.abrirUrlExterna(linkAula, context),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('Abrir este curso en el Aula',
                      style: TextStyle(fontSize: 12)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _advertencia(BuildContext context, IconData icono, String titulo,
      String texto) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cessumGold.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, size: 18, color: cessumGold),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo,
                    style: CessumType.heading(12, color: cessumInk(context))),
                const SizedBox(height: 2),
                Text(texto,
                    style:
                        CessumType.body(11.5, color: cessumMuted(context))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
//  SELECTOR CON BUSCADOR (nada de listas planas largas)
// =====================================================================
class _Opcion {
  final int valor;
  final String titulo;
  final String subtitulo;
  final String etiqueta;
  final Color? etiquetaColor;
  const _Opcion({
    required this.valor,
    required this.titulo,
    this.subtitulo = '',
    this.etiqueta = '',
    this.etiquetaColor,
  });
}

class _PickerBuscable extends StatefulWidget {
  final String titulo;
  final String hint;
  final List<_Opcion> opciones;
  const _PickerBuscable({
    required this.titulo,
    required this.hint,
    required this.opciones,
  });

  @override
  State<_PickerBuscable> createState() => _PickerBuscableState();
}

class _PickerBuscableState extends State<_PickerBuscable> {
  final TextEditingController _busca = TextEditingController();

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  static String _n(String s) {
    var t = s.toLowerCase().trim();
    const acentos = {
      'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u', 'ñ': 'n',
    };
    acentos.forEach((k, v) => t = t.replaceAll(k, v));
    return t;
  }

  @override
  Widget build(BuildContext context) {
    final q = _n(_busca.text);
    final lista = q.isEmpty
        ? widget.opciones
        : widget.opciones
            .where((o) =>
                _n(o.titulo).contains(q) || _n(o.subtitulo).contains(q))
            .toList();
    return AlertDialog(
      title: Text(widget.titulo, style: const TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 480,
        height: 440,
        child: Column(
          children: [
            TextField(
              controller: _busca,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: widget.hint,
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: lista.isEmpty
                  ? Center(
                      child: Text('Sin coincidencias',
                          style:
                              CessumType.body(13, color: cessumMuted(context))),
                    )
                  : ListView.builder(
                      itemCount: lista.length,
                      itemBuilder: (ctx, i) {
                        final o = lista[i];
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.chevron_right,
                              size: 20, color: cessumRed),
                          title: Text(o.titulo,
                              style: const TextStyle(fontSize: 13)),
                          subtitle: o.subtitulo.isEmpty
                              ? null
                              : Text(o.subtitulo,
                                  style: const TextStyle(fontSize: 11)),
                          trailing: o.etiqueta.isEmpty
                              ? null
                              : Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: (o.etiquetaColor ?? cessumGold)
                                        .withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    o.etiqueta,
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color:
                                            o.etiquetaColor ?? cessumGold),
                                  ),
                                ),
                          onTap: () => Navigator.pop(context, o.valor),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
      ],
    );
  }
}

// =====================================================================
//  CATÁLOGO DE PLANTILLAS Y PLANES
// =====================================================================
class _Programa {
  final String nombre;
  final String asset;
  final int labelBottom;
  final List<String> materias;
  const _Programa({
    required this.nombre,
    required this.asset,
    required this.labelBottom,
    required this.materias,
  });
}

// Generado desde cartas.json (no editar a mano salvo el plan).
const List<_Programa> _kProgramas = [
  _Programa(
    nombre: 'Maestría en Educación',
    asset: 'assets/images/portada_maestria_educacion.png',
    labelBottom: 677,
    materias: [
      'Corrientes Pedagógicas Contemporáneas',
      'Fundamentos de Psicología Educativa',
      'Liderazgo en Educación',
      'Diversidad y Aprendizaje Inclusivo',
      'Gestión de Proyectos Educativos',
      'Evaluación del Aprendizaje',
      'TIC en la Educación',
      'Neuroeducación',
      'Ética y Legislación en Educación',
      'Diseño Curricular y Planificación Educativa',
      'Educación Socioemocional: Estrategias y Herramientas',
      'Metodología de la Investigación Educativa',
    ],
  ),
  _Programa(
    nombre: 'Maestría en Educación Inclusiva',
    asset: 'assets/images/portada_maestria_educacion_inclusiva.png',
    labelBottom: 677,
    materias: [
      'Introducción y Evolución de la Educación Inclusiva',
      'Inclusión Educativa y Contexto Sociopolítico',
      'Desarrollo Infantil y Adolescente',
      'Fundamentos Legales de la Educación Inclusiva',
      'Tecnologías de la Información y Comunicación (TIC) para la Inclusión',
      'Práctica docente y proyectos de mejora escolar y comunitaria',
      'Trastornos del Neurodesarrollo y su Impacto en la Educación',
      'Ajustes Razonables para la Inclusión',
      'Inclusión en la Educación Básica',
      'Inclusión en la Educación Media Superior y Superior',
      'Estrategias de Comunicación para favorecer la Inclusión',
      'Diseño de Programas de Inclusión Educativa',
      'Diversidad Cultural y Social en la Educación Inclusiva',
      'Metodología de la Investigación',
      'Seminario de Tesis 1: Elaboración del Proyecto de Investigación',
      'Seminario de Tesis 2: Ejecución y Redacción del Proyecto de Investigación',
    ],
  ),
  _Programa(
    nombre: 'Maestría en Pedagogía',
    asset: 'assets/images/portada_maestria_pedagogia.png',
    labelBottom: 677,
    materias: [
      'Historia y evolución de la pedagogía',
      'Teorías y enfoques pedagógicos',
      'Diseño y evaluación curricular',
      'Métodos, técnicas y recursos para las prácticas inclusivas',
      'Psicología del aprendizaje',
      'Teorías del desarrollo humano',
      'Evaluación del aprendizaje',
      'Diseño de ambientes de aprendizaje',
      'Fundamentos de las tecnologías educativas',
      'Diseño y desarrollo de materiales educativos digitales',
      'Tecnología en el aula',
      'Evaluación de tecnologías educativas',
      'Metodología de la investigación en educación',
      'Diseño y análisis de datos en investigaciones educativas',
      'Técnicas de escritura académica y elaboración de tesis',
      'Seminarios de investigación en pedagogía',
    ],
  ),
  _Programa(
    nombre: 'Maestría en Psicopedagogía',
    asset: 'assets/images/portada_maestria_psicopedagogia.png',
    labelBottom: 677,
    materias: [
      'Neurodesarrollo',
      'Corrientes Pedagógicas Contemporáneas',
      'Fundamentos de la Investigación',
      'Diversidad e inclusión educativa',
      'Psicopatología del Niño y el Adolescente',
      'Currículum y procesos de enseñanza-aprendizaje',
      'Seminario de Investigación I',
      'Ajustes razonables y estrategias didácticas inclusivas',
      'Evaluación Psicopedagógica',
      'TIC aplicada a la Educación',
      'Seminario de Investigación II',
      'Desarrollo socioemocional y educación inclusiva',
      'Intervención Psicopedagógica',
      'La práctica docente reflexiva (planeación, implementación y evaluación)',
      'Seminario de Investigación III',
      'Diseño universal para el aprendizaje',
    ],
  ),
  _Programa(
    nombre: 'Doctorado en Educación con Énfasis en Investigación',
    asset: 'assets/images/portada_doctorado_investigacion.png',
    labelBottom: 620,
    materias: [
      'Metodología I: Metodologías de Investigación Cualitativa',
      'Seminario de Tesis I: El proyecto de Investigación',
      'Epistemología I',
      'Corrientes pedagógicas contemporáneas',
      'Metodología II: Metodologías de Investigación Cuantitativa',
      'Seminario de Tesis II: El estado del arte, la revisión de la literatura y el marco teórico',
      'Epistemología II',
      'El cambio organizacional',
      'Metodología III: Técnicas e instrumentos de recolección de datos',
      'Seminario de Tesis III: Recolección de datos',
      'Epistemología III',
      'Planeación y Evaluación educativa',
      'Teoría del Curriculum',
      'Metodología IV: Técnicas y estadísticos de análisis',
      'Seminario de Tesis IV: Análisis de datos y redacción de la Tesis de Grado',
      'Epistemología IV',
    ],
  ),
  _Programa(
    nombre: 'Doctorado en Ciencias de la Educación',
    asset: 'assets/images/portada_doctorado_ciencias.png',
    labelBottom: 677,
    materias: [
      'Laboratorio Pedagógico: el estudio de clase',
      'Epistemología y Ciencias de la Educación',
      'Introducción a la Investigación de las Ciencias de la Educación',
      'Perspectivas Internacionales Comparadas',
      'Laboratorio Pedagógico: la Clase Pública',
      'Debates Psicopedagógicos Contemporáneos',
      'Seminario de Investigación I',
      'Análisis Comparado de Sistemas Educativos',
      'Didáctica y Pedagogía Experimental I',
      'Teoría, diseño y evaluación del currículo',
      'Seminario de Investigación II',
      'Revisión de Escuelas Experimentales I',
      'Didáctica y Pedagogía Experimental II',
      'Diseño, Implementación y Evaluación de Proyectos Socioformativos',
      'Seminario de Investigación III',
      'Revisión de Escuelas Experimentales II',
    ],
  ),
];

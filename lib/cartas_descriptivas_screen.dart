import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'cartas_service.dart';
import 'copiar_rico.dart';

class CartasDescriptivasScreen extends StatefulWidget {
  /// Si viene con valor (ej. el programa del estudiante), la pantalla muestra
  /// SOLO ese programa y cambia el título a "Plan de estudios". Si es null
  /// (caso de los profesores), muestra todos los programas como siempre.
  final String? programaFijo;

  const CartasDescriptivasScreen({super.key, this.programaFijo});

  @override
  State<CartasDescriptivasScreen> createState() =>
      _CartasDescriptivasScreenState();
}

// Normaliza un nombre de programa para comparar sin acentos ni mayúsculas.
String _normPrograma(String s) {
  s = s.toLowerCase().trim();
  const con = 'áàäâãéèëêíìïîóòöôõúùüûñ';
  const sin = 'aaaaaeeeeiiiiooooouuuun';
  for (var i = 0; i < con.length; i++) {
    s = s.replaceAll(con[i], sin[i]);
  }
  return s;
}

class _CartasDescriptivasScreenState extends State<CartasDescriptivasScreen> {
  late Future<List<ProgramaCartas>> _futureCartas;
  final TextEditingController _buscadorCtrl = TextEditingController();
  String _busqueda = '';

  @override
  void initState() {
    super.initState();
    _futureCartas = CartasService.obtener();
    _buscadorCtrl.addListener(() {
      if (mounted) setState(() {
        _busqueda = _buscadorCtrl.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _buscadorCtrl.dispose();
    super.dispose();
  }

  Future<void> _recargar() async {
    await CartasService.obtener(forzarRecarga: true);
    if (mounted) setState(() {
      _futureCartas = CartasService.obtener();
    });
  }

  void _volverAlMenu() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _abrirDetalle(Asignatura a, String programa) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _AsignaturaDetalleScreen(asignatura: a, programa: programa),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        title: Text(
          widget.programaFijo != null ? 'Plan de estudios' : 'Cartas Descriptivas',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        elevation: 2,
        actions: [
          IconButton(
            icon: const Icon(Icons.home),
            tooltip: 'Inicio',
            onPressed: _volverAlMenu,
          ),
        ],
      ),
      body: Column(
        children: [
          // Barra de busqueda fija arriba
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: TextField(
              controller: _buscadorCtrl,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Buscar asignatura por nombre...',
                prefixIcon: const Icon(Icons.search, color: cessumRed),
                suffixIcon: _busqueda.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, color: Colors.black45),
                        tooltip: 'Limpiar',
                        onPressed: () => _buscadorCtrl.clear(),
                      ),
                filled: true,
                fillColor: const Color(0xFFF2F2F2),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: cessumRed, width: 1.5),
                ),
              ),
            ),
          ),

          // Contenido
          Expanded(
            child: FutureBuilder<List<ProgramaCartas>>(
              future: _futureCartas,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: cessumRed),
                  );
                }

                if (snapshot.hasError || snapshot.data == null) {
                  return _ErrorView(onReintentar: _recargar);
                }

                final todosProgramas = snapshot.data!;
                // Si se pidió un programa fijo (estudiante), filtramos a ese.
                final programas = widget.programaFijo == null
                    ? todosProgramas
                    : todosProgramas
                        .where((p) =>
                            _normPrograma(p.programa) ==
                            _normPrograma(widget.programaFijo!))
                        .toList();
                if (programas.isEmpty) {
                  return _VacioView(onReintentar: _recargar);
                }

                if (_busqueda.isNotEmpty) {
                  return _ResultadosBusqueda(
                    programas: programas,
                    busqueda: _busqueda,
                    onAbrir: _abrirDetalle,
                  );
                }

                return RefreshIndicator(
                  color: cessumRed,
                  onRefresh: _recargar,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                    itemCount: programas.length,
                    itemBuilder: (context, i) {
                      return _ProgramaSeccion(
                        programa: programas[i],
                        onAbrir: _abrirDetalle,
                        initiallyExpanded: widget.programaFijo != null,
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// Seccion plegable de un programa, con sus asignaturas adentro
class _ProgramaSeccion extends StatelessWidget {
  final ProgramaCartas programa;
  final void Function(Asignatura, String) onAbrir;
  final bool initiallyExpanded;

  const _ProgramaSeccion({
    required this.programa,
    required this.onAbrir,
    this.initiallyExpanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final tiene = programa.asignaturas.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.only(bottom: 8),
          iconColor: cessumRed,
          collapsedIconColor: cessumRed,
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: cessumRed.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.menu_book, color: cessumRed, size: 20),
          ),
          title: Text(
            programa.programa,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
              height: 1.25,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              tiene
                  ? '${programa.asignaturas.length} asignatura(s)'
                  : 'Aun no hay cartas en este programa',
              style: const TextStyle(fontSize: 12, color: Colors.black45),
            ),
          ),
          children: tiene
              ? _agruparPorPeriodo(programa.asignaturas)
                  .map((entry) => _SemestreSeccion(
                        periodo: entry.key,
                        asignaturas: entry.value,
                        programa: programa.programa,
                        onAbrir: onAbrir,
                      ))
                  .toList()
              : const [
                  Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Text(
                      'Proximamente se agregaran las cartas de este programa.',
                      style: TextStyle(fontSize: 12.5, color: Colors.black54),
                    ),
                  ),
                ],
        ),
      ),
    );
  }
}

// Agrupa las asignaturas de un programa por periodo (semestre / cuatrimestre /
// trimestre) y devuelve los grupos ordenados por numero de periodo.
List<MapEntry<String, List<Asignatura>>> _agruparPorPeriodo(
    List<Asignatura> asignaturas) {
  final mapa = <String, List<Asignatura>>{};
  for (final a in asignaturas) {
    final clave =
        a.semestre.trim().isNotEmpty ? a.semestre.trim() : 'Otras asignaturas';
    mapa.putIfAbsent(clave, () => []).add(a);
  }
  final entradas = mapa.entries.toList();
  entradas.sort((x, y) => _ordenPeriodo(x.key).compareTo(_ordenPeriodo(y.key)));
  return entradas;
}

// Convierte el ordinal del periodo en un numero para poder ordenarlo.
int _ordenPeriodo(String periodo) {
  final p = periodo.toLowerCase();
  const ordinales = <String, int>{
    'primer': 1,
    'segundo': 2,
    'tercer': 3,
    'cuarto': 4,
    'quinto': 5,
    'sexto': 6,
    'septimo': 7,
    'séptimo': 7,
    'octavo': 8,
    'noveno': 9,
    'decimo': 10,
    'décimo': 10,
  };
  for (final e in ordinales.entries) {
    if (p.contains(e.key)) return e.value;
  }
  return 99; // lo desconocido se va al final
}

// Submenu plegable de un periodo (semestre), con sus asignaturas adentro
class _SemestreSeccion extends StatelessWidget {
  final String periodo;
  final List<Asignatura> asignaturas;
  final String programa;
  final void Function(Asignatura, String) onAbrir;

  const _SemestreSeccion({
    required this.periodo,
    required this.asignaturas,
    required this.programa,
    required this.onAbrir,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFFAF7F0),
          borderRadius: BorderRadius.circular(10),
        ),
        clipBehavior: Clip.antiAlias,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
            childrenPadding: const EdgeInsets.only(bottom: 4),
            iconColor: cessumGold,
            collapsedIconColor: cessumGold,
            leading: const Icon(Icons.calendar_today, color: cessumGold, size: 18),
            title: Text(
              periodo,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
            subtitle: Text(
              '${asignaturas.length} asignatura(s)',
              style: const TextStyle(fontSize: 11, color: Colors.black45),
            ),
            children: asignaturas
                .map((a) => _AsignaturaTile(
                      asignatura: a,
                      programa: programa,
                      onAbrir: onAbrir,
                      mostrarSubtitulo: false,
                    ))
                .toList(),
          ),
        ),
      ),
    );
  }
}

// Renglon de una asignatura
class _AsignaturaTile extends StatelessWidget {
  final Asignatura asignatura;
  final String programa;
  final void Function(Asignatura, String) onAbrir;
  final bool mostrarPrograma;
  final bool mostrarSubtitulo;

  const _AsignaturaTile({
    required this.asignatura,
    required this.programa,
    required this.onAbrir,
    this.mostrarPrograma = false,
    this.mostrarSubtitulo = true,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onAbrir(asignatura, programa),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.description_outlined, color: cessumGold, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    asignatura.denominacion,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                      height: 1.25,
                    ),
                  ),
                  if (mostrarSubtitulo) ...[
                    const SizedBox(height: 2),
                    Text(
                      mostrarPrograma
                          ? programa
                          : (asignatura.semestre.isNotEmpty
                              ? asignatura.semestre
                              : 'Asignatura'),
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Colors.black45,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: Colors.black26, size: 20),
          ],
        ),
      ),
    );
  }
}

// Lista plana de resultados cuando hay texto en el buscador
class _ResultadosBusqueda extends StatelessWidget {
  final List<ProgramaCartas> programas;
  final String busqueda;
  final void Function(Asignatura, String) onAbrir;

  const _ResultadosBusqueda({
    required this.programas,
    required this.busqueda,
    required this.onAbrir,
  });

  @override
  Widget build(BuildContext context) {
    final resultados = <_Coincidencia>[];
    for (final p in programas) {
      for (final a in p.asignaturas) {
        if (a.denominacion.toLowerCase().contains(busqueda)) {
          resultados.add(_Coincidencia(asignatura: a, programa: p.programa));
        }
      }
    }

    if (resultados.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(32),
        children: [
          const SizedBox(height: 40),
          Icon(Icons.search_off, size: 56, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          const Text(
            'Sin resultados',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'No se encontro ninguna asignatura con "$busqueda".',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: Colors.black54),
          ),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      itemCount: resultados.length,
      itemBuilder: (context, i) {
        final r = resultados[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: _AsignaturaTile(
            asignatura: r.asignatura,
            programa: r.programa,
            onAbrir: onAbrir,
            mostrarPrograma: true,
          ),
        );
      },
    );
  }
}

class _Coincidencia {
  final Asignatura asignatura;
  final String programa;
  const _Coincidencia({required this.asignatura, required this.programa});
}

// =====================================================
// PANTALLA DE DETALLE DE UNA ASIGNATURA
// =====================================================
class _AsignaturaDetalleScreen extends StatefulWidget {
  final Asignatura asignatura;
  final String programa;

  const _AsignaturaDetalleScreen({
    required this.asignatura,
    required this.programa,
  });

  @override
  State<_AsignaturaDetalleScreen> createState() =>
      _AsignaturaDetalleScreenState();
}

class _AsignaturaDetalleScreenState extends State<_AsignaturaDetalleScreen> {
  Asignatura get asignatura => widget.asignatura;
  String get programa => widget.programa;
  bool _generandoPdf = false;

  // (14-sep) DESCARGA EN PDF CON LA IMAGEN INSTITUCIONAL.
  // Copiar con formato dependía de dónde se pegara: cada docente terminaba
  // con una versión distinta de la misma carta. El PDF lo arma el Guardián
  // con las mismas piezas que la constancia y el kárdex —membrete, banda
  // roja, Montserrat—, así que sale igual para todos.
  Future<void> _descargarPdf() async {
    setState(() => _generandoPdf = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final uri = Uri.parse('$guardianUrl?accion=carta_descriptiva_pdf'
          '&programa=${Uri.encodeComponent(programa)}'
          '&clave_asignatura=${Uri.encodeComponent(asignatura.clave)}'
          '&denominacion=${Uri.encodeComponent(asignatura.denominacion)}'
          '&lento=1&z=${DateTime.now().millisecondsSinceEpoch}');
      final resp = await http.get(uri).timeout(const Duration(seconds: 120));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] != true) {
        messenger.showSnackBar(SnackBar(
            backgroundColor: cessumRed,
            content: Text('${data['error'] ?? 'No se pudo generar el PDF.'}')));
        return;
      }
      final url = (data['pdfUrl'] ?? '').toString();
      if (url.isEmpty) {
        messenger.showSnackBar(const SnackBar(
            backgroundColor: cessumRed,
            content: Text('El Guardián no devolvió el enlace del PDF.')));
        return;
      }
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
          backgroundColor: cessumRed,
          content: Text('No se pudo generar el PDF: '
              '${'$e'.replaceAll('Exception: ', '')}')));
    } finally {
      if (mounted) setState(() => _generandoPdf = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        title: const Text(
          'Carta Descriptiva',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        elevation: 2,
        actions: [
          _generandoPdf
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    ),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  tooltip: 'Descargar en PDF (institucional)',
                  onPressed: _descargarPdf,
                ),
          IconButton(
            icon: const Icon(Icons.content_copy),
            tooltip: 'Copiar con formato (Word/Docs)',
            onPressed: () => _copiarConFormato(context),
          ),
          IconButton(
            icon: const Icon(Icons.short_text),
            tooltip: 'Copiar solo texto',
            onPressed: () => _copiarSoloTexto(context),
          ),
          IconButton(
            icon: const Icon(Icons.home),
            tooltip: 'Inicio',
            onPressed: () =>
                Navigator.of(context).popUntil((route) => route.isFirst),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Encabezado: denominacion + programa
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  programa.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: cessumRed,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  asignatura.denominacion,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _InfoChip(
                      icon: Icons.calendar_today,
                      etiqueta: 'Ciclo',
                      valor: asignatura.semestre,
                    ),
                    _InfoChip(
                      icon: Icons.tag,
                      etiqueta: 'Clave',
                      valor: asignatura.clave,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Fines de aprendizaje
          _Seccion(
            titulo: 'Fines de aprendizaje o formación',
            icono: Icons.flag_outlined,
            contenido: asignatura.fines,
          ),
          const SizedBox(height: 16),

          // Contenido tematico
          _Seccion(
            titulo: 'Contenido temático',
            icono: Icons.list_alt,
            contenido: asignatura.contenido,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // --- Copiado de la carta (con formato y en texto plano) -----------------
  List<String> _lineasCarta(String s) => s
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();

  String _escHtml(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  String _bloqueHtml(String contenido) {
    final ls = _lineasCarta(contenido);
    if (ls.isEmpty) return '<p style="color:#666;">No especificado.</p>';
    if (ls.length == 1) return '<p>${_escHtml(ls.first)}</p>';
    final li = ls.map((l) => '<li>${_escHtml(l)}</li>').join();
    return '<ul>$li</ul>';
  }

  String _bloquePlano(String contenido) {
    final ls = _lineasCarta(contenido);
    if (ls.isEmpty) return 'No especificado.';
    if (ls.length == 1) return ls.first;
    return ls.map((l) => '\u2022 $l').join('\n');
  }

  String _armarHtmlCarta() {
    return '<div style="font-family:Arial,Helvetica,sans-serif;color:#1a1a1a;font-size:13.5px;line-height:1.5;">'
        '<p style="color:#B11D29;font-weight:bold;font-size:11px;letter-spacing:.5px;margin:0 0 2px;">${_escHtml(programa.toUpperCase())}</p>'
        '<h2 style="margin:0 0 4px;color:#111;font-size:19px;">${_escHtml(asignatura.denominacion)}</h2>'
        '<p style="margin:0 0 12px;color:#555;"><b>Ciclo:</b> ${_escHtml(asignatura.semestre)} &nbsp;&middot;&nbsp; <b>Clave:</b> ${_escHtml(asignatura.clave)}</p>'
        '<h3 style="color:#B11D29;margin:14px 0 4px;border-bottom:1px solid #e6e6e6;padding-bottom:3px;">Fines de aprendizaje o formaci\u00f3n</h3>'
        '${_bloqueHtml(asignatura.fines)}'
        '<h3 style="color:#B11D29;margin:14px 0 4px;border-bottom:1px solid #e6e6e6;padding-bottom:3px;">Contenido tem\u00e1tico</h3>'
        '${_bloqueHtml(asignatura.contenido)}'
        '</div>';
  }

  String _armarPlanoCarta() {
    final b = StringBuffer();
    b.writeln('CARTA DESCRIPTIVA');
    b.writeln(asignatura.denominacion);
    b.writeln();
    b.writeln('Programa: $programa');
    if (asignatura.semestre.trim().isNotEmpty) {
      b.writeln('Ciclo: ${asignatura.semestre}');
    }
    if (asignatura.clave.trim().isNotEmpty) {
      b.writeln('Clave: ${asignatura.clave}');
    }
    b.writeln();
    b.writeln('FINES DE APRENDIZAJE O FORMACI\u00d3N');
    b.writeln(_bloquePlano(asignatura.fines));
    b.writeln();
    b.writeln('CONTENIDO TEM\u00c1TICO');
    b.writeln(_bloquePlano(asignatura.contenido));
    return b.toString().trimRight();
  }

  Future<void> _copiarConFormato(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await copiarConFormato(_armarHtmlCarta(), _armarPlanoCarta());
    messenger.showSnackBar(SnackBar(
      content: Text(ok
          ? 'Carta copiada con formato. P\u00e9gala en Word o Google Docs.'
          : 'No se pudo copiar. Usa "Copiar solo texto".'),
      backgroundColor: ok ? const Color(0xFF1E7D32) : cessumRed,
    ));
  }

  Future<void> _copiarSoloTexto(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await copiarTexto(_armarPlanoCarta());
    messenger.showSnackBar(SnackBar(
      content: Text(ok ? 'Texto de la carta copiado.' : 'No se pudo copiar.'),
      backgroundColor: ok ? const Color(0xFF1E7D32) : cessumRed,
    ));
  }
}

// Chip de informacion (semestre, clave, ciclo)
class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String etiqueta;
  final String valor;

  const _InfoChip({
    required this.icon,
    required this.etiqueta,
    required this.valor,
  });

  @override
  Widget build(BuildContext context) {
    final texto = valor.trim().isEmpty ? 'No especificado' : valor.trim();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cessumGold.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cessumGold.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: cessumGold),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                etiqueta,
                style: const TextStyle(fontSize: 9.5, color: Colors.black45),
              ),
              Text(
                texto,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// Seccion con titulo y contenido (los renglones se muestran como vinetas)
class _Seccion extends StatelessWidget {
  final String titulo;
  final IconData icono;
  final String contenido;

  const _Seccion({
    required this.titulo,
    required this.icono,
    required this.contenido,
  });

  @override
  Widget build(BuildContext context) {
    final lineas = contenido
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icono, size: 18, color: cessumRed),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  titulo,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: cessumRed,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Divider(height: 18),
          if (lineas.isEmpty)
            const Text(
              'No especificado.',
              style: TextStyle(fontSize: 13, color: Colors.black54),
            )
          else if (lineas.length == 1)
            Text(
              lineas.first,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.5,
                color: Colors.black87,
              ),
            )
          else
            ...lineas.map(
              (l) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 7),
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: cessumGold,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        l,
                        style: const TextStyle(
                          fontSize: 13.5,
                          height: 1.45,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// Vista de error de conexion
class _ErrorView extends StatelessWidget {
  final Future<void> Function() onReintentar;

  const _ErrorView({required this.onReintentar});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 40),
        Icon(Icons.cloud_off, size: 56, color: Colors.grey.shade400),
        const SizedBox(height: 16),
        const Text(
          'No se pudieron cargar las cartas',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Revisa tu conexion a internet e intenta de nuevo.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Colors.black54),
        ),
        const SizedBox(height: 20),
        Center(
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: cessumRed,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            onPressed: onReintentar,
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar'),
          ),
        ),
      ],
    );
  }
}

// Vista cuando el JSON cargo pero esta vacio
class _VacioView extends StatelessWidget {
  final Future<void> Function() onReintentar;

  const _VacioView({required this.onReintentar});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 40),
        Icon(Icons.folder_open, size: 56, color: Colors.grey.shade400),
        const SizedBox(height: 16),
        const Text(
          'Aun no hay cartas disponibles',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 20),
        Center(
          child: TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: cessumRed),
            onPressed: onReintentar,
            icon: const Icon(Icons.refresh),
            label: const Text('Actualizar'),
          ),
        ),
      ],
    );
  }
}

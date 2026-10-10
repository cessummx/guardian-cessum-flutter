import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'captura_calificaciones_screen.dart' show guardianUrl;

import 'constants.dart';
import 'cessum_ui.dart';

/// Generador de referencias APA 7 (muchos tipos) con guía rápida.
/// Las partes que van en cursiva se marcan con <i></i>; al copiar se usa
/// texto enriquecido (text/html) para que la cursiva se pegue ya aplicada
/// en Word/Google Docs. 100% local (no requiere backend).
class ApaReferenciasScreen extends StatefulWidget {
  final String nombre;
  final String programa;
  const ApaReferenciasScreen({super.key, this.nombre = '', this.programa = ''});

  @override
  State<ApaReferenciasScreen> createState() => _ApaReferenciasScreenState();
}

class _Campo {
  final String clave;
  final String label;
  final String hint;
  const _Campo(this.clave, this.label, {this.hint = ''});
}

class _TipoFuente {
  final String nombre;
  final List<_Campo> campos;
  final String formato;
  final String ejemplo;
  const _TipoFuente(this.nombre, this.campos, this.formato, this.ejemplo);
}

class _ApaReferenciasScreenState extends State<ApaReferenciasScreen> {
  final Map<String, TextEditingController> _c = {};
  final List<String> _referencias = []; // guardan HTML con <i>
  // (24-sep) Pegar la cita como venga y que la IA llene los campos.
  final _cIa = TextEditingController();
  bool _iaCargando = false;
  String _iaAviso = '';

  TextEditingController _ctrl(String k) =>
      _c.putIfAbsent(k, () => TextEditingController());
  String _v(String k) => _ctrl(k).text.trim();
  String _it(String s) => s.isEmpty ? '' : '<i>$s</i>';

  static const _autores =
      _Campo('autores', 'Autor(es)', hint: 'Apellido, A. A.; Apellido, B. B.');
  static const _anio = _Campo('anio', 'Año', hint: 'ej. 2024');
  static const _fecha = _Campo('fecha', 'Fecha completa',
      hint: 'Año, día de mes — ej. 2024, 15 de marzo');
  static const _url = _Campo('url', 'URL (enlace)', hint: 'https://…');

  static final List<_TipoFuente> _tipos = [
    _TipoFuente(
      'Libro',
      const [
        _autores,
        _anio,
        _Campo('titulo', 'Título del libro'),
        _Campo('edicion', 'Edición (opcional)', hint: 'ej. 3ª'),
        _Campo('editorial', 'Editorial'),
      ],
      'Autor. (Año). *Título del libro* (edición). Editorial.',
      'Sánchez, R. (2021). *Didáctica de las ciencias* (2ª ed.). Trillas.',
    ),
    _TipoFuente(
      'Capítulo de libro',
      const [
        _autores,
        _anio,
        _Campo('capitulo', 'Título del capítulo'),
        _Campo('editores', 'Editor(es) del libro', hint: 'A. Apellido'),
        _Campo('libro', 'Título del libro'),
        _Campo('paginas', 'Páginas', hint: 'ej. 45-67'),
        _Campo('editorial', 'Editorial'),
      ],
      'Autor. (Año). Título del capítulo. En Eds. (Ed.), *Título del libro* (pp. xx-xx). Editorial.',
      'Mares, G. (2019). El lenguaje en el aula. En J. Pérez (Ed.), *Aprendizaje y escuela* (pp. 30-58). UNAM.',
    ),
    _TipoFuente(
      'Artículo de revista científica',
      const [
        _autores,
        _anio,
        _Campo('articulo', 'Título del artículo'),
        _Campo('revista', 'Nombre de la revista'),
        _Campo('volumen', 'Volumen'),
        _Campo('numero', 'Número (opcional)'),
        _Campo('paginas', 'Páginas', hint: 'ej. 10-25'),
        _Campo('doi', 'DOI (opcional)', hint: 'solo el código o el enlace'),
      ],
      'Autor. (Año). Título del artículo. *Revista, Volumen*(Número), páginas. https://doi.org/xxx',
      'Ribes, E. (2018). Teoría de la conducta. *Acta Comportamentalia, 26*(1), 5-20. https://doi.org/10.xxxx',
    ),
    _TipoFuente(
      'Artículo de revista (divulgación)',
      const [
        _autores,
        _fecha,
        _Campo('articulo', 'Título del artículo'),
        _Campo('revista', 'Nombre de la revista'),
        _Campo('volumen', 'Volumen (opcional)'),
        _Campo('paginas', 'Páginas (opcional)'),
        _url,
      ],
      'Autor. (Año, mes). Título del artículo. *Revista, Volumen*, páginas. URL',
      'López, M. (2023, marzo). Neuroeducación hoy. *Educar, 45*, 12-15. https://…',
    ),
    _TipoFuente(
      'Artículo de periódico / nota',
      const [
        _autores,
        _fecha,
        _Campo('articulo', 'Título de la nota'),
        _Campo('periodico', 'Nombre del periódico'),
        _url,
      ],
      'Autor. (Año, día de mes). Título de la nota. *Nombre del periódico*. URL',
      'Gómez, A. (2024, 3 de mayo). Reforma educativa. *El Universal*. https://…',
    ),
    _TipoFuente(
      'Página o sitio web',
      const [
        _autores,
        _fecha,
        _Campo('titulo', 'Título de la página'),
        _Campo('sitio', 'Nombre del sitio (opcional)'),
        _url,
      ],
      'Autor. (Año, día de mes). *Título de la página*. Nombre del sitio. URL',
      'OMS. (2023, 10 de enero). *Salud mental*. Organización Mundial de la Salud. https://…',
    ),
    _TipoFuente(
      'Tesis o disertación',
      const [
        _autores,
        _anio,
        _Campo('titulo', 'Título de la tesis'),
        _Campo('tipotesis', 'Tipo', hint: 'ej. Tesis de maestría'),
        _Campo('institucion', 'Institución'),
        _Campo('repositorio', 'Repositorio (opcional)'),
        _url,
      ],
      'Autor. (Año). *Título* [Tipo, Institución]. Repositorio. URL',
      'Miranda, J. (2022). *Lectura inicial* [Tesis de doctorado, ITSON]. RI-ITSON. https://…',
    ),
    _TipoFuente(
      'Informe o reporte',
      const [
        _autores,
        _anio,
        _Campo('titulo', 'Título del informe'),
        _Campo('numinforme', 'N.º de informe (opcional)'),
        _Campo('editorial', 'Institución que publica'),
        _url,
      ],
      'Autor/Institución. (Año). *Título del informe* (N.º). Institución. URL',
      'INEE. (2019). *La educación obligatoria en México* (Informe 2019). INEE. https://…',
    ),
    _TipoFuente(
      'Ley o documento oficial',
      const [
        _Campo('titulo', 'Nombre de la ley/documento'),
        _anio,
        _Campo('publicacion', 'Publicación oficial',
            hint: 'ej. Diario Oficial de la Federación'),
        _Campo('pais', 'País (opcional)'),
        _url,
      ],
      'Nombre de la ley. (Año). Publicación oficial. URL',
      'Ley General de Educación. (2019). Diario Oficial de la Federación. https://…',
    ),
    _TipoFuente(
      'Ponencia / congreso',
      const [
        _autores,
        _fecha,
        _Campo('titulo', 'Título de la ponencia'),
        _Campo('tipocontrib', 'Tipo', hint: 'ej. Ponencia, Cartel'),
        _Campo('congreso', 'Nombre del congreso'),
        _Campo('lugar', 'Lugar', hint: 'Ciudad, País'),
        _url,
      ],
      'Autor. (Año, día de mes). *Título* [Tipo]. Nombre del congreso, Lugar. URL',
      'Farfán, E. (2024, 20 de junio). *Modos de interacción* [Ponencia]. COINEDU, Navojoa, México. https://…',
    ),
    _TipoFuente(
      'Video de YouTube',
      const [
        _Campo('canal', 'Autor o canal'),
        _fecha,
        _Campo('titulo', 'Título del video'),
        _url,
      ],
      'Autor/Canal. (Año, día de mes). *Título del video* [Video]. YouTube. URL',
      'CESSUM. (2024, 1 de febrero). *Cómo citar en APA* [Video]. YouTube. https://…',
    ),
    _TipoFuente(
      'Entrada de blog',
      const [
        _autores,
        _fecha,
        _Campo('titulo', 'Título de la entrada'),
        _Campo('blog', 'Nombre del blog'),
        _url,
      ],
      'Autor. (Año, día de mes). Título de la entrada. *Nombre del blog*. URL',
      'Ruiz, P. (2023, 8 de julio). Evaluar sin exámenes. *EduBlog*. https://…',
    ),
    _TipoFuente(
      'Publicación en red social',
      const [
        _Campo('autores', 'Autor', hint: 'Nombre o institución'),
        _Campo('usuario', 'Usuario', hint: 'ej. @cessum'),
        _fecha,
        _Campo('contenido', 'Texto de la publicación',
            hint: 'primeras ~20 palabras'),
        _Campo('plataforma', 'Plataforma', hint: 'ej. X, Facebook, Instagram'),
        _url,
      ],
      'Autor [@usuario]. (Año, día de mes). *Contenido* [publicación]. Plataforma. URL',
      'CESSUM [@cessum]. (2024, 5 de mayo). *Inscripciones abiertas…* [Publicación]. Facebook. https://…',
    ),
    _TipoFuente(
      'Entrada de diccionario/enciclopedia',
      const [
        _Campo('autores', 'Autor o institución'),
        _anio,
        _Campo('entrada', 'Palabra o entrada'),
        _Campo('diccionario', 'Título del diccionario'),
        _Campo('editorial', 'Editorial (opcional)'),
        _url,
      ],
      'Autor. (Año). Entrada. En *Título del diccionario*. Editorial. URL',
      'RAE. (2023). Aprendizaje. En *Diccionario de la lengua española*. https://…',
    ),
  ];

  late _TipoFuente _tipo;

  @override
  void initState() {
    super.initState();
    _tipo = _tipos.first;
  }

  @override
  void dispose() {
    _cIa.dispose();
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _fmtAutores(String raw) {
    final parts =
        raw.split(';').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return '';
    if (parts.length == 1) return parts[0];
    if (parts.length == 2) return '${parts[0]} & ${parts[1]}';
    return '${parts.sublist(0, parts.length - 1).join(', ')}, & ${parts.last}';
  }

  String _fechaParen() {
    final f = _v('fecha');
    if (f.isNotEmpty) return '($f)';
    final a = _v('anio');
    return a.isEmpty ? '(s. f.)' : '($a)';
  }

  /// Genera la referencia con <i></i> donde corresponde cursiva.
  String _generarHtml() {
    final aut = _fmtAutores(_v('autores'));
    final a = aut.isEmpty ? '' : '$aut ';
    final f = _fechaParen();
    String url() => _v('url').isEmpty ? '' : ' ${_v('url')}';

    switch (_tipo.nombre) {
      case 'Libro':
        final ed = _v('edicion').isEmpty ? '' : ' (${_v('edicion')} ed.)';
        return '$a$f. ${_it(_v('titulo'))}$ed. ${_v('editorial')}.';
      case 'Capítulo de libro':
        final pp = _v('paginas').isEmpty ? '' : ' (pp. ${_v('paginas')})';
        return '$a$f. ${_v('capitulo')}. En ${_v('editores')} (Ed.), '
            '${_it(_v('libro'))}$pp. ${_v('editorial')}.';
      case 'Artículo de revista científica':
        final revVol = _v('revista') +
            (_v('volumen').isEmpty ? '' : ', ${_v('volumen')}');
        final num = _v('numero').isEmpty ? '' : '(${_v('numero')})';
        final pgs = _v('paginas').isEmpty ? '' : ', ${_v('paginas')}';
        final doi = _v('doi').isEmpty
            ? ''
            : ' https://doi.org/${_v('doi').replaceAll('https://doi.org/', '')}';
        return '$a$f. ${_v('articulo')}. ${_it(revVol)}$num$pgs.$doi';
      case 'Artículo de revista (divulgación)':
        final revVol = _v('revista') +
            (_v('volumen').isEmpty ? '' : ', ${_v('volumen')}');
        final pgs = _v('paginas').isEmpty ? '' : ', ${_v('paginas')}';
        return '$a$f. ${_v('articulo')}. ${_it(revVol)}$pgs.${url()}';
      case 'Artículo de periódico / nota':
        return '$a$f. ${_v('articulo')}. ${_it(_v('periodico'))}.${url()}';
      case 'Página o sitio web':
        final sitio = _v('sitio').isEmpty ? '' : ' ${_v('sitio')}.';
        return '$a$f. ${_it(_v('titulo'))}.$sitio${url()}';
      case 'Tesis o disertación':
        final tt = _v('tipotesis').isEmpty ? 'Tesis' : _v('tipotesis');
        final rep = _v('repositorio').isEmpty ? '' : ' ${_v('repositorio')}.';
        return '$a$f. ${_it(_v('titulo'))} [$tt, ${_v('institucion')}].$rep${url()}';
      case 'Informe o reporte':
        final ni = _v('numinforme').isEmpty ? '' : ' (${_v('numinforme')})';
        return '$a$f. ${_it(_v('titulo'))}$ni. ${_v('editorial')}.${url()}';
      case 'Ley o documento oficial':
        final pais = _v('pais').isEmpty ? '' : ' ${_v('pais')}.';
        return '${_v('titulo')}. $f. ${_v('publicacion')}.$pais${url()}';
      case 'Ponencia / congreso':
        final tc = _v('tipocontrib').isEmpty ? 'Ponencia' : _v('tipocontrib');
        return '$a$f. ${_it(_v('titulo'))} [$tc]. ${_v('congreso')}, ${_v('lugar')}.${url()}';
      case 'Video de YouTube':
        return '${_v('canal')} $f. ${_it(_v('titulo'))} [Video]. YouTube.${url()}';
      case 'Entrada de blog':
        return '$a$f. ${_v('titulo')}. ${_it(_v('blog'))}.${url()}';
      case 'Publicación en red social':
        final us = _v('usuario').isEmpty ? '' : ' [${_v('usuario')}]';
        final plat = _v('plataforma').isEmpty ? '' : ' ${_v('plataforma')}.';
        return '${_v('autores')}$us. $f. ${_it(_v('contenido'))} [Publicación].$plat${url()}';
      case 'Entrada de diccionario/enciclopedia':
        final ed = _v('editorial').isEmpty ? '' : ' ${_v('editorial')}.';
        return '$a$f. ${_v('entrada')}. En ${_it(_v('diccionario'))}.$ed${url()}';
      default:
        return '';
    }
  }

  String _plain(String h) =>
      h.replaceAll(RegExp(r'</?i>'), '').replaceAll('<br>', '\n');

  void _agregar() {
    final ref = _generarHtml().replaceAll(RegExp(r'[ \t]+'), ' ').trim();
    if (_plain(ref).length < 8) {
      _msg('Llena al menos el autor, la fecha y el título.');
      return;
    }
    setState(() {
      _referencias.add(ref);
      _referencias.sort(
          (x, y) => _plain(x).toLowerCase().compareTo(_plain(y).toLowerCase()));
      for (final c in _c.values) {
        c.clear();
      }
    });
  }

  void _msg(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(t), backgroundColor: cessumRed));
  }

  /// Copia con formato (text/html) usando un contenedor temporal + execCommand,
  /// para que la cursiva se pegue ya aplicada en Word/Docs.
  void _copiarRico(String htmlText) {
    final plain = _plain(htmlText);
    try {
      final cont = html.DivElement()
        ..setInnerHtml(htmlText,
            treeSanitizer: html.NodeTreeSanitizer.trusted)
        ..style.position = 'fixed'
        ..style.left = '-9999px'
        ..style.whiteSpace = 'pre-wrap';
      html.document.body!.append(cont);
      final sel = html.window.getSelection();
      final range = html.Range()..selectNodeContents(cont);
      sel!
        ..removeAllRanges()
        ..addRange(range);
      final ok = html.document.execCommand('copy');
      sel.removeAllRanges();
      cont.remove();
      if (!ok) Clipboard.setData(ClipboardData(text: plain));
    } catch (_) {
      Clipboard.setData(ClipboardData(text: plain));
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Copiado con cursiva. Pégalo en Word o Google Docs.'),
        backgroundColor: Colors.green));
  }

  List<TextSpan> _spans(String s) {
    final spans = <TextSpan>[];
    final re = RegExp(r'<i>(.*?)</i>', dotAll: true);
    int last = 0;
    for (final m in re.allMatches(s)) {
      if (m.start > last) {
        spans.add(TextSpan(text: s.substring(last, m.start)));
      }
      spans.add(TextSpan(
          text: m.group(1),
          style: const TextStyle(fontStyle: FontStyle.italic)));
      last = m.end;
    }
    if (last < s.length) spans.add(TextSpan(text: s.substring(last)));
    return spans;
  }

  String _asterToI(String s) =>
      s.replaceAllMapped(RegExp(r'\*(.*?)\*'), (m) => '<i>${m[1]}</i>');

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: cessumBg(context),
        appBar: AppBar(
          backgroundColor: cessumRed,
          foregroundColor: Colors.white,
          title: const Text('Referencias APA 7'),
          bottom: const TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(text: 'Referencias'),
              Tab(text: 'Guía'),
            ],
          ),
        ),
        body: TabBarView(
          children: [_tabReferencias(), _tabGuia()],
        ),
      ),
    );
  }

  /// (24-sep) La IA identifica el tipo de fuente y llena los campos a partir de
  /// una cita pegada como venga (desordenada, de otro formato, con DOI o URL).
  /// No inventa: lo que no viene en el texto se avisa como faltante.
  Future<void> _llenarConIa() async {
    final texto = _cIa.text.trim();
    if (texto.length < 8) {
      _msg('Pega primero la cita o los datos de la fuente.');
      return;
    }
    setState(() {
      _iaCargando = true;
      _iaAviso = '';
    });
    try {
      final tipos = _tipos
          .map((t) => {'nombre': t.nombre, 'campos': t.campos.map((c) => c.clave).toList()})
          .toList();
      final r = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({'accion': 'apa_ia_estructurar', 'texto': texto, 'tipos': tipos}))
          .timeout(const Duration(seconds: 60));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo reconocer la fuente.');
      final nombre = '${d['tipo'] ?? ''}';
      final tipo = _tipos.where((t) => t.nombre == nombre).toList();
      if (tipo.isEmpty) throw Exception('No reconocí el tipo de fuente. Elígelo y llena los campos a mano.');
      final campos = Map<String, dynamic>.from((d['campos'] as Map?) ?? const {});
      setState(() {
        _tipo = tipo.first;
        for (final c in _tipo.campos) {
          _ctrl(c.clave).text = '${campos[c.clave] ?? ''}'.trim();
        }
        final faltan = ((d['faltan'] as List?) ?? [])
            .map((k) => _tipo.campos.where((c) => c.clave == '$k').map((c) => c.label).join())
            .where((x) => x.isNotEmpty)
            .toList();
        _iaAviso = 'Identifiqué: ${_tipo.nombre}. Revisa los campos antes de agregar.'
            '${faltan.isNotEmpty ? ' No venían en tu texto: ${faltan.join(', ')}.' : ''}'
            '${'${d['nota'] ?? ''}'.trim().isNotEmpty ? ' ${d['nota']}' : ''}';
      });
    } catch (e) {
      _msg('$e'.replaceFirst('Exception: ', ''));
    }
    if (mounted) setState(() => _iaCargando = false);
  }

  Widget _tarjetaIa() {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cessumGold.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cessumGold.withValues(alpha: 0.45)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.auto_awesome, color: cessumGold, size: 18),
          SizedBox(width: 6),
          Expanded(
            child: Text('¿Tienes la cita desordenada? Pégala y la IA llena los campos',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ),
        ]),
        const SizedBox(height: 8),
        TextField(
          controller: _cIa,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
            hintText: 'Ej. ribes emilio 2018 teoria de la conducta acta comportamentalia vol 26 num 1 pp 5-20',
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: cessumRed),
            onPressed: _iaCargando ? null : _llenarConIa,
            icon: _iaCargando
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.auto_fix_high, size: 18),
            label: Text(_iaCargando ? 'Leyendo…' : 'Llenar con IA'),
          ),
          const SizedBox(width: 8),
          if (_cIa.text.isNotEmpty || _iaAviso.isNotEmpty)
            TextButton(
              onPressed: () => setState(() {
                _cIa.clear();
                _iaAviso = '';
              }),
              child: const Text('Limpiar'),
            ),
        ]),
        if (_iaAviso.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(_iaAviso, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ]),
    );
  }

  Widget _tabReferencias() {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        _tarjetaIa(),
        const Text('¿Qué vas a citar?',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 6),
        DropdownButtonFormField<_TipoFuente>(
          value: _tipo,
          isExpanded: true,
          decoration: const InputDecoration(
              prefixIcon: Icon(Icons.menu_book, color: cessumRed),
              border: OutlineInputBorder()),
          items: _tipos
              .map((t) => DropdownMenuItem(value: t, child: Text(t.nombre)))
              .toList(),
          onChanged: (v) => setState(() => _tipo = v ?? _tipo),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cessumGold.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: cessumGold.withValues(alpha: 0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Formato:',
                  style:
                      TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
              Text.rich(TextSpan(
                  style: TextStyle(fontSize: 12.5, color: cessumInk(context)),
                  children: _spans(_asterToI(_tipo.formato)))),
              const SizedBox(height: 6),
              const Text('Ejemplo:',
                  style:
                      TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
              Text.rich(TextSpan(
                  style: TextStyle(fontSize: 12.5, color: cessumInk(context)),
                  children: _spans(_asterToI(_tipo.ejemplo)))),
              const SizedBox(height: 6),
              Text('La cursiva ya se copia aplicada; pégala en Word.',
                  style: TextStyle(fontSize: 11, color: cessumMuted(context))),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ..._tipo.campos.map(_campoWidget),
        const SizedBox(height: 4),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
              backgroundColor: cessumRed, foregroundColor: Colors.white),
          icon: const Icon(Icons.add),
          label: const Text('Generar y agregar referencia'),
          onPressed: _agregar,
        ),
        const SizedBox(height: 16),
        if (_referencias.isNotEmpty) ...[
          Row(
            children: [
              Expanded(
                child: Text('Mis referencias (${_referencias.length})',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
              ),
              TextButton.icon(
                icon: const Icon(Icons.copy_all, size: 18),
                label: const Text('Copiar todas'),
                onPressed: () =>
                    _copiarRico(_referencias.join('<br><br>')),
              ),
            ],
          ),
          Text(
            'En tu documento, ponlas en orden alfabético, con sangría francesa '
            'y a doble espacio.',
            style: TextStyle(fontSize: 11.5, color: cessumMuted(context)),
          ),
          const SizedBox(height: 6),
          ..._referencias.map((r) => Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text.rich(TextSpan(
                            style: TextStyle(
                                fontSize: 13.5, color: cessumInk(context)),
                            children: _spans(r))),
                      ),
                      IconButton(
                        icon:
                            const Icon(Icons.copy, size: 18, color: cessumRed),
                        onPressed: () => _copiarRico(r),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline,
                            size: 18, color: Colors.redAccent),
                        onPressed: () =>
                            setState(() => _referencias.remove(r)),
                      ),
                    ],
                  ),
                ),
              )),
        ],
      ],
    );
  }

  Widget _campoWidget(_Campo c) {
    final multilinea = c.clave == 'contenido';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: _ctrl(c.clave),
        maxLines: multilinea ? 2 : 1,
        decoration: InputDecoration(
          labelText: c.label,
          hintText: c.hint.isEmpty ? null : c.hint,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _tabGuia() {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        _bloque('¿Qué es APA 7?',
            'Es el estilo de la American Psychological Association (7ª edición) '
                'para citar fuentes y dar formato a trabajos académicos. Tiene dos '
                'partes: las citas dentro del texto y la lista de referencias al final.'),
        _bloque('Cita dentro del texto',
            'Parentética: (Apellido, año, p. 12). Ejemplo: …como señala la teoría '
                '(Ribes, 2018).\n'
                'Narrativa: Apellido (año) afirma que… Ejemplo: Ribes (2018) afirma que…\n'
                'Cita textual: agrega la página (p. 12) o (pp. 12-14).'),
        _bloque('Varios autores',
            'Dos autores: usa "&" en la referencia y en la cita parentética '
                '(López & Mares, 2020).\n'
                'Tres o más: en el TEXTO se abrevia con "et al." → (López et al., 2020). '
                'En la lista de referencias se escriben todos (hasta 20).'),
        _bloque('Lista de referencias',
            '• Orden alfabético por apellido del primer autor.\n'
                '• Sangría francesa: la primera línea al margen y las siguientes con '
                'sangría.\n'
                '• A doble espacio.\n'
                '• Sin numerar ni viñetas.'),
        _bloque('¿Qué va en cursiva?',
            'El título del libro, de la revista y del periódico van en cursiva. '
                'El título de un artículo o capítulo NO va en cursiva. Esta app ya '
                'aplica la cursiva por ti al copiar.'),
        _bloque('Fechas',
            'Si no hay fecha, se usa (s. f.). Para web, periódicos y redes se pone '
                'la fecha completa: (2024, 15 de marzo).'),
        const SizedBox(height: 8),
        Text(
          'Esta guía es un apoyo rápido; para casos especiales consulta el Manual '
          'APA 7 o el Centro de Escritura APA.',
          style: TextStyle(fontSize: 11.5, color: cessumMuted(context)),
        ),
      ],
    );
  }

  Widget _bloque(String titulo, String texto) {
    return Card(
      color: Theme.of(context).cardColor,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo,
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: cessumRed)),
            const SizedBox(height: 6),
            Text(texto, style: const TextStyle(fontSize: 13, height: 1.35)),
          ],
        ),
      ),
    );
  }
}

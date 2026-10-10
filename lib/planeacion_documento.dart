// =====================================================================
//  planeacion_documento.dart · CESSUM · Aula CESSUM
//  EL DOCUMENTO DE LA PLANEACIÓN, GENERADO DESDE LA PROPIA APP.
//
//  Antes esto vivía en planeacion.html, fuera de la app: el docente tocaba
//  «descargar» y se abría otra pestaña que armaba el archivo. Funcionaba,
//  pero el documento quedaba fuera del ciclo de compilación —si se rompía,
//  nadie se enteraba hasta que alguien no podía descargar— y obligaba a
//  mantener la misma lógica en dos lenguajes.
//
//  Ahora se arma aquí, con el mismo patrón que la app ya usa para el CSV de
//  grupos y los banners semanales: se construye el HTML, se envuelve en un
//  Blob y se descarga. Sin paquetes nuevos y sin abrir pestañas.
//
//    · Word  → Blob application/msword. Word lo abre y respeta el formato.
//    · PDF   → iframe oculto + print(): el navegador ofrece «Guardar como
//              PDF» con el diseño intacto.
//
//  Dos usos con el mismo diseño institucional:
//    documentoPlaneacion(...)  la planeación completa, ya generada.
//    documentoPlantilla(...)   la plantilla en blanco precargada con los
//                              datos curriculares y una ficha por sesión.
// =====================================================================

import 'dart:convert';
import 'dart:html' as html; // la app es Flutter web, igual que el CSV de grupos

const String _kLogo = 'https://app.cessum.mx/logo-cessum.png';
/// (4-oct-2026) Identidad CESSUM según el kit oficial: MONTSERRAT dominante (títulos en 800-900, texto en 400-600);
/// Playfair Display SOLO como acento, en itálica, para el lema y las frases institucionales. Rojo intenso con vino,
/// dorado como filete y como etiqueta. Emblemas: logotipo oficial, isotipo del venado y la línea institucional con la CCT.
const String _kTit = "'Montserrat','Segoe UI',Arial,sans-serif";
const String _kIsotipo = 'https://app.cessum.mx/icons/Icon-192.png';
const String _kSerif = "'Playfair Display',Georgia,'Times New Roman',serif";
const String _kSans = "'Montserrat','Segoe UI',Arial,sans-serif";
const String _kFuentes = '<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>'
    '<link href="https://fonts.googleapis.com/css2?family=Montserrat:wght@400;500;600;700;800;900&family=Playfair+Display:ital,wght@1,500;1,600&display=swap" rel="stylesheet">';

String _esc(Object? v) => (v ?? '')
    .toString()
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

String _nl(Object? v) => _esc(v).replaceAll('\n', '<br>');

// (8-oct-2026) Antes cada lista se castaba con `.map((e) => Map<String, dynamic>.from(e as Map))`
// sin protección: un solo elemento nulo o mal formado (plausible en una planeación generada por
// IA o editada a mano) tronaba toda la generación del documento, dejando al docente sin Word ni
// PDF. Ahora se descarta en silencio el elemento que no es un mapa, en vez de tronar por su culpa.
List<Map<String, dynamic>> _comoListaMapas(dynamic l) {
  if (l is! List) return const [];
  final out = <Map<String, dynamic>>[];
  for (final x in l) {
    if (x is Map) out.add(Map<String, dynamic>.from(x));
  }
  return out;
}

String _txt(Map<String, dynamic>? m, String k) => '${m?[k] ?? ''}'.trim();

// ── Cabecera institucional ──────────────────────────────────────────
String _cabecera() => '''
<table style="width:100%;border-collapse:collapse;margin-bottom:8px">
  <tr>
    <td style="width:170px;vertical-align:middle"><img src="$_kLogo" width="160" height="48" style="width:160px;height:auto"></td>
    <td style="vertical-align:middle;text-align:right">
      <div style="font-family:$_kTit;font-size:14px;font-weight:800;color:#8E1620;line-height:1.2;letter-spacing:-.1px">Centro de Estudios Superiores del Mayo, A.C.</div>
      <div style="font-family:$_kSerif;font-style:italic;font-size:10px;color:#B8842C;margin-top:2px">Formamos a los profesionales del Mayo</div>
      <div style="font-family:$_kSans;font-size:8.5px;color:#6B6257;margin-top:3px;letter-spacing:.3px">CCT 26PSU0110Z · Leona Vicario 104, Col. Juárez, Navojoa, Sonora</div>
    </td>
  </tr>
</table>
<div style="height:4px;background:#C8202F"></div>
<div style="height:2px;background:#8E1620"></div>
<div style="height:2px;background:#B8842C;margin-bottom:18px"></div>
<div style="text-align:center;margin-bottom:18px">
  <div style="font-family:$_kSans;font-size:8.5px;font-weight:700;color:#B8842C;letter-spacing:3px">VICERRECTORÍA ACADÉMICA</div>
  <div style="font-family:$_kTit;font-size:27px;font-weight:900;color:#1F1A17;margin-top:4px;line-height:1.1;letter-spacing:-.4px">Planeación didáctica</div>
  <div style="width:56px;height:2px;background:#B8842C;margin:8px auto"></div>
  <div style="font-family:$_kSans;font-size:9px;font-weight:600;color:#C8202F;letter-spacing:2.5px">MODELO CESSUM · INTERACCIONES COMPLEJAS</div>
</div>''';

String _h2(String t) =>
    '<h2 style="font-family:$_kTit;font-size:13.5px;font-weight:800;color:#8E1620;text-transform:uppercase;letter-spacing:.6px;border-bottom:1.5px solid #B8842C;'
    'padding-bottom:4px;margin-top:20px;margin-bottom:8px">$t</h2>';

// ── Datos curriculares ──────────────────────────────────────────────
String _fichaCurricular(Map<String, dynamic> c, Map<String, dynamic> d, String docente) {
  String fila(String k, String v) => v.trim().isEmpty
      ? ''
      : '<tr>'
          '<td style="background:#FBF7EF;color:#B8842C;font-weight:bold;font-size:10px;'
          'padding:6px 10px;border:1px solid #EADFCB;width:150px">$k</td>'
          '<td style="font-size:11px;padding:6px 10px;border:1px solid #EADFCB">${_esc(v)}</td></tr>';

  final gen = _txt(c, 'generacion');
  final gru = _txt(c, 'grupo');
  final ses = '${d['sesiones'] ?? ''}';
  final porque = _txt(d, 'porque');

  return '${_h2('DATOS CURRICULARES')}'
      '<table style="width:100%;border-collapse:collapse;margin-bottom:14px">'
      '${fila('Asignatura', _txt(c, 'denominacion'))}'
      '${fila('Clave', _txt(c, 'clave'))}'
      '${fila('Programa', _txt(c, 'programa'))}'
      '${fila('Modalidad', _txt(c, 'modalidad'))}'
      '${fila('Generación y grupo', gen + (gru.isNotEmpty ? ' · Grupo $gru' : ''))}'
      '${fila('Ubicación en el plan', _txt(c, 'semestre'))}'
      '${fila('Créditos', _txt(c, 'creditos'))}'
      '${fila('Docente', docente.isNotEmpty ? docente : _txt(c, 'docente'))}'
      '${fila('Sesiones', ses + (porque.isNotEmpty ? ' — $porque' : ''))}'
      '</table>';
}

String _finesYTemario(Map<String, dynamic> c) {
  final b = StringBuffer();
  final fines = _txt(c, 'fines');
  if (fines.isNotEmpty) {
    b.write(_h2('FINES DE APRENDIZAJE'));
    // Los fines suelen venir como varias líneas, una por propósito. Puestos
    // en un solo párrafo justificado, Word estira los espacios y quedan
    // huecos enormes entre palabras. Como lista se leen bien.
    final partes = fines
        .split(RegExp(r'\r?\n'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (partes.length > 1) {
      b.write('<ul style="font-size:11px;line-height:1.5;margin:0 0 14px 18px">');
      for (final f in partes) {
        b.write('<li style="margin-bottom:4px">${_esc(f)}</li>');
      }
      b.write('</ul>');
    } else {
      b.write('<p style="font-size:11px;line-height:1.55;text-align:justify">${_esc(fines)}</p>');
    }
  }
  final temas = ((c['temas'] as List?) ?? []).map((e) => '$e').toList();
  if (temas.isNotEmpty) {
    b.write(_h2('CONTENIDO TEMÁTICO'));
    b.write('<ol style="font-size:11px;line-height:1.5;margin:0 0 14px 20px">');
    for (final t in temas) {
      b.write('<li>${_esc(t)}</li>');
    }
    b.write('</ol>');
  }
  return b.toString();
}

// ── El abridor: se pinta distinto de todo lo demás porque es la pieza
//    que el docente tiene que localizar de un vistazo durante la clase.
// (4-oct-2026) Herramientas del diplomado: tipo de abridor, tipo de pregunta y la conducción de cada pregunta.
const Map<String, String> _tipoAbrDoc = {'referir': 'REFERIR', 'significado': 'SIGNIFICADO', 'explicar': 'EXPLICAR', 'anticipar': 'ANTICIPAR'};
const Map<String, String> _tipoPregDoc = {'incorporacion': 'INCORPORACIÓN CONCEPTUAL', 'derivacion': 'DERIVACIÓN DEL SISTEMA', 'simple': 'SIMPLE'};
String _abridor(String texto, Object? nivel, String cuando, {bool vacio = false, Map<String, dynamic> x = const {}}) {
  final n = '${nivel ?? ''}';
  String v(String k) => '${x[k] ?? ''}'.trim();
  final etq = 'ABRIDOR'
      '${(n.isNotEmpty && n != '0' && n != 'null') ? ' · NIVEL $n' : ''}'
      '${_tipoAbrDoc[v('tipoAbridor')] != null ? ' · ${_tipoAbrDoc[v('tipoAbridor')]}' : ''}'
      '${_tipoPregDoc[v('tipoPregunta')] != null ? ' · ${_tipoPregDoc[v('tipoPregunta')]}' : ''}'
      '${v('modalidad').isNotEmpty ? ' · ${_esc(v('modalidad').toUpperCase())}' : ''}'
      '${cuando.isNotEmpty ? ' · ${_esc(cuando)}' : ''}';
  final terminos = ((x['terminos'] as List?) ?? []).map((e) => '$e').where((e) => e.isNotEmpty).toList();
  final seguimiento = ((x['seguimiento'] as List?) ?? []).map((e) => '$e').where((e) => e.isNotEmpty).toList();
  String fila(String t, String c) => '<div style="font-size:9.5px;color:#5E544D;margin-top:2px"><b>$t:</b> ${_esc(c)}</div>';
  final ficha = StringBuffer();
  if (v('respuestaEsperada').isNotEmpty) ficha.write(fila('Respuesta esperada', v('respuestaEsperada')));
  if (terminos.isNotEmpty) ficha.write(fila('Términos que deben aparecer', terminos.join(', ')));
  if (v('siEsPertinente').isNotEmpty) ficha.write(fila('Si es pertinente', v('siEsPertinente')));
  if (v('siNoEsPertinente').isNotEmpty) ficha.write(fila('Si no es pertinente', v('siNoEsPertinente')));
  if (seguimiento.isNotEmpty) ficha.write(fila('Seguimiento', seguimiento.join(' · ')));
  final cuerpo = vacio
      ? '<div style="min-height:26px"></div>'
      : '<div style="font-size:10.5px;font-style:italic;color:#6B4E14;line-height:1.4">${_esc(texto)}</div>';
  return '<div style="background:#F6EBD3;border-left:3px solid #B8842C;padding:6px 9px;margin-top:5px">'
      '<div style="font-size:8px;letter-spacing:1.5px;color:#B8842C;font-weight:bold">$etq</div>'
      '$cuerpo$ficha</div>';
}

// ── Ficha de sesión: llena, o en blanco para la plantilla ────────────
String _fichaSesion(Map<String, dynamic> s, int n, {required bool plantilla}) {
  String lineas(List acciones, int alto) {
    if (acciones.isNotEmpty) {
      final li = acciones.map((a) => '<li>${_esc(a)}</li>').join();
      return '<ul style="margin:0 0 0 16px;padding:0;font-size:10.5px;line-height:1.5">$li</ul>';
    }
    return '<div style="min-height:${alto}px"></div>';
  }

  String momento(String nombre, String color, Map<String, dynamic> m, bool conDeslig) {
    final acciones = (m['acciones'] as List?) ?? [];
    final abridores = _comoListaMapas(m['abridores']);
    final min = '${m['minutos'] ?? ''}';
    final prop = _txt(m, 'proposito');
    final desl = _txt(m, 'condicionDesligamiento');
    final abr = _txt(m, 'abridor');
    final sost = _txt(m, 'comoSostener');
    final resp = _txt(m, 'respuestasEsperadas');
    final evid = _txt(m, 'evidenciaDeLogro');

    final b = StringBuffer();
    b.write('<tr>'
        '<td style="border:1px solid #EADFCB;padding:8px;vertical-align:top;width:90px;background:#FBF7EF">'
        '<div style="font-size:9.5px;font-weight:bold;letter-spacing:1px;color:$color">$nombre</div>'
        '<div style="font-size:9px;color:#6B6257;margin-top:3px">'
        '${min.isNotEmpty && min != '0' ? '$min min' : '____ min'}</div></td>'
        '<td style="border:1px solid #EADFCB;padding:8px;vertical-align:top">');
    if (prop.isNotEmpty) {
      b.write('<div style="font-size:10px;font-style:italic;color:#6B6257;margin-bottom:4px">${_esc(prop)}</div>');
    }
    if (_txt(m, 'ruta').isNotEmpty) {
      b.write('<div style="font-size:10px;margin-bottom:4px"><b>Lámina de propósito:</b> ${_esc(_txt(m, 'ruta'))}</div>');
    }
    b.write(lineas(acciones, 40));
    if (conDeslig) {
      if (desl.isNotEmpty) {
        b.write('<div style="background:#F7F3EA;padding:6px 9px;margin-top:5px;font-size:10px">'
            '<b>Lo que el estudiante debe traer:</b> ${_esc(desl)}</div>');
      } else if (plantilla) {
        b.write('<div style="background:#F7F3EA;padding:6px 9px;margin-top:5px;font-size:9.5px;color:#999">'
            '<b>Lo que el estudiante debe traer</b> (condición de desligamiento):'
            '<div style="min-height:24px"></div></div>');
      }
    }
    if (abr.isNotEmpty) {
      b.write(_abridor(abr, m['abridorNivel'], '', x: {'tipoAbridor': m['abridorTipo'], 'tipoPregunta': m['preguntaTipo'], 'terminos': m['terminos']}));
    } else if (plantilla) {
      b.write(_abridor('', null, '', vacio: true));
    }
    for (final a in abridores) {
      b.write(_abridor('${a['texto'] ?? ''}', a['nivel'], '${a['cuando'] ?? ''}', x: a));
    }
    if (sost.isNotEmpty) {
      b.write('<div style="font-size:10px;color:#6B6257;margin-top:5px"><b>Cómo sostenerlo:</b> ${_esc(sost)}</div>');
    }
    if (resp.isNotEmpty) {
      b.write('<div style="font-size:10px;color:#6B6257;margin-top:3px"><b>Respuestas esperadas:</b> ${_esc(resp)}</div>');
    }
    if (evid.isNotEmpty) {
      b.write('<div style="font-size:10px;color:#6B6257;margin-top:3px"><b>Evidencia de logro:</b> ${_esc(evid)}</div>');
    }
    b.write('</td></tr>');
    return b.toString();
  }

  final tema = _txt(s, 'tema');
  final crit = _txt(s, 'criterioLogro');
  final nivel = '${s['nivel'] ?? ''}';
  final nivNom = _txt(s, 'nivelNombre');
  final recursos = _comoListaMapas(s['recursos']);
  final tarea = _txt(s, 'tarea');

  final b = StringBuffer();
  b.write('<div style="page-break-inside:avoid;margin-bottom:16px">'
      '<table style="width:100%;border-collapse:collapse">'
      '<tr><td colspan="2" style="background:#C8202F;color:#fff;padding:8px 11px;border-bottom:3px solid #B8842C">'
      '<span style="font-family:$_kTit;font-size:13.5px;font-weight:900;letter-spacing:.3px">SESIÓN $n</span>'
      '${tema.isEmpty ? '' : '<span style="font-family:$_kSans;font-size:10.5px;font-weight:600"> · ${_esc(tema)}</span>'}');
  if (nivel.isNotEmpty && nivel != '0') {
    b.write('<span style="float:right;font-size:9px;color:#F6EBD3">NIVEL $nivel'
        '${nivNom.isNotEmpty ? ' · ${_esc(nivNom).toUpperCase()}' : ''}</span>');
  }
  b.write('</td></tr>'
      '<tr><td colspan="2" style="border:1px solid #EADFCB;padding:8px;background:#FBF7EF">'
      '<div style="font-size:9px;letter-spacing:1px;color:#B8842C;font-weight:bold">CRITERIO DE LOGRO</div>'
      '<div style="font-size:10.5px;line-height:1.45">'
      '${crit.isEmpty ? '<div style="min-height:26px"></div>' : _esc(crit)}</div></td></tr>');
  // (3-oct) Si la sesión de un grupo VIRTUAL quedó con dinámicas de salón aun después de la corrección automática, el documento lo dice
  // para que quien revisa (o el docente) lo vea sin tener que leer todo.
  final avisoMod = _txt(s, '_avisoModalidad');
  if (avisoMod.isNotEmpty) {
    b.write('<tr><td colspan="2" style="border:1px solid #EADFCB;padding:7px 9px;background:#FBE9E7">'
        '<div style="font-size:9px;letter-spacing:1px;color:#C8202F;font-weight:bold">REVISAR MODALIDAD</div>'
        '<div style="font-size:10px;line-height:1.45">${_esc(avisoMod)} '
        'Este grupo es virtual: conviene reescribir esas actividades para Meet y Moodle.</div></td></tr>');
  }
  b.write(momento('INICIO', '#1E7B34', Map<String, dynamic>.from((s['inicio'] as Map?) ?? {}), false));
  b.write(momento('DESARROLLO', '#C8202F', Map<String, dynamic>.from((s['desarrollo'] as Map?) ?? {}), true));
  b.write(momento('CIERRE', '#B8842C', Map<String, dynamic>.from((s['cierre'] as Map?) ?? {}), false));

  b.write('<tr><td style="border:1px solid #EADFCB;padding:8px;background:#FBF7EF;'
      'font-size:9.5px;font-weight:bold;color:#6B6257">RECURSOS</td>'
      '<td style="border:1px solid #EADFCB;padding:8px">');
  if (recursos.isNotEmpty) {
    b.write('<ul style="margin:0 0 0 16px;padding:0;font-size:10.5px;line-height:1.5">');
    for (final r in recursos) {
      final tipo = _txt(r, 'tipo');
      final para = _txt(r, 'para');
      final frag = _txt(r, 'fragmento'), obs = _txt(r, 'queObservar'), pa = _txt(r, 'preguntaAntes'), pd = _txt(r, 'preguntaDespues');
      final ref = _txt(r, 'ref');
      b.write('<li><b>${_esc(r['titulo'])}</b>'
          '${tipo.isNotEmpty ? ' (${_esc(tipo)})' : ''}'
          '${ref.isNotEmpty ? '<br><span style="color:#8A5F10">📖 ${_esc(ref)}</span>' : ''}'
          '${para.isNotEmpty ? ' — ${_esc(para)}' : ''}'
          '${frag.isNotEmpty ? '<br>Fragmento: ${_esc(frag)}' : ''}'
          '${obs.isNotEmpty ? '<br>Qué observar: ${_esc(obs)}' : ''}'
          '${pa.isNotEmpty ? '<br><i>Pregunta antes:</i> ${_esc(pa)}' : ''}'
          '${pd.isNotEmpty ? '<br><i>Pregunta después:</i> ${_esc(pd)}' : ''}</li>');
    }
    b.write('</ul>');
  } else {
    b.write('<div style="min-height:34px"></div>');
  }
  b.write('</td></tr>');

  // (4-oct-2026) El avance del proyecto que toca a esta sesión.
  final ap = Map<String, dynamic>.from((s['avanceProyecto'] as Map?) ?? {});
  if (_txt(ap, 'hito').isNotEmpty) {
    b.write('<tr><td style="border:1px solid #EADFCB;padding:8px;background:#FBF7EF;'
        'font-size:9.5px;font-weight:bold;color:#6B6257">PROYECTO</td>'
        '<td style="border:1px solid #EADFCB;padding:8px;font-size:10.5px;line-height:1.5">'
        '<b>Hito:</b> ${_esc(ap['hito'])}'
        '${_txt(ap, 'enSesion').isNotEmpty ? '<br><b>En la sesión:</b> ${_esc(ap['enSesion'])}' : ''}'
        '${_txt(ap, 'paraCasa').isNotEmpty ? '<br><b>Antes de la siguiente:</b> ${_esc(ap['paraCasa'])}' : ''}'
        '</td></tr>');
  }

  if (tarea.isNotEmpty || plantilla) {
    b.write('<tr><td style="border:1px solid #EADFCB;padding:8px;background:#FBF7EF;'
        'font-size:9.5px;font-weight:bold;color:#6B6257">TAREA</td>'
        '<td style="border:1px solid #EADFCB;padding:8px;font-size:10.5px">'
        '${tarea.isEmpty ? '<div style="min-height:22px"></div>' : _esc(tarea)}</td></tr>');
  }
  b.write('</table></div>');
  return b.toString();
}

String _firmas(String docente, String modeloVersion, bool plantilla) => '''
<table style="width:100%;margin-top:34px;page-break-inside:avoid">
  <tr>
    <td style="width:50%;text-align:center;padding:0 20px">
      <div style="border-top:1px solid #333;margin:0 20px 5px"></div>
      <div style="font-size:11px;font-weight:bold">${_esc(docente)}</div>
      <div style="font-size:9px;color:#6B6257">Docente</div></td>
    <td style="width:50%;text-align:center;padding:0 20px">
      <div style="border-top:1px solid #333;margin:0 20px 5px"></div>
      <div style="font-size:11px;font-weight:bold">Vicerrectoría Académica</div>
      <div style="font-size:9px;color:#6B6257">Validación</div></td>
  </tr>
</table>
<div style="height:2px;background:#B8842C;margin-top:22px"></div>
<div style="height:4px;background:#C8202F;margin-bottom:8px"></div>
<table style="width:100%;border-collapse:collapse;page-break-inside:avoid">
  <tr>
    <td style="width:46px;vertical-align:middle"><img src="$_kIsotipo" width="38" height="38" style="width:38px;height:38px"></td>
    <td style="vertical-align:middle">
      <div style="font-family:$_kTit;font-size:10px;font-weight:900;color:#C8202F;letter-spacing:2px">EL MAYO ES CESSUM</div>
      <div style="font-family:$_kSerif;font-style:italic;font-size:12px;color:#8E1620;margin-top:1px">Más que una universidad, una familia.</div>
      <div style="font-family:$_kSans;font-size:8px;color:#6B6257;margin-top:2px;line-height:1.45">
        Planeación didáctica bajo el modelo CESSUM de promoción de aprendizajes complejos${modeloVersion.isNotEmpty ? ' · versión ${_esc(modeloVersion)}' : ''}.
        Centro de Estudios Superiores del Mayo, A.C. · CCT 26PSU0110Z · Leona Vicario 104, Col. Juárez, Navojoa, Sonora.
        ${plantilla ? 'Plantilla para llenado. Los datos curriculares vienen del programa oficial de la asignatura.' : ''}</div>
    </td>
  </tr>
</table>''';

// ── El documento completo ───────────────────────────────────────────
String documentoPlaneacion({
  required Map<String, dynamic> contexto,
  required Map<String, dynamic> planeacion,
  String docente = '',
  String modeloVersion = '',
}) {
  final c = Map<String, dynamic>.from((contexto['curricular'] as Map?) ?? {});
  final d = Map<String, dynamic>.from((contexto['dosificacion'] as Map?) ?? {});
  final b = StringBuffer();
  b.write(_cabecera());
  b.write(_fichaCurricular(c, d, docente));
  b.write(_finesYTemario(c));

  final enc = Map<String, dynamic>.from((planeacion['encuadre'] as Map?) ?? {});
  final af = _txt(enc, 'analisisFuncional');
  final hd = _txt(enc, 'historiaDisponible');
  final pr = _txt(enc, 'proposito');
  if (af.isNotEmpty || hd.isNotEmpty || pr.isNotEmpty) {
    b.write(_h2('ENCUADRE DIDÁCTICO'));
    if (af.isNotEmpty) {
      b.write('<p style="font-size:11px;line-height:1.55;text-align:justify">'
          '<b>Análisis funcional del propósito.</b> ${_nl(af)}</p>');
    }
    if (hd.isNotEmpty) {
      b.write('<p style="font-size:11px;line-height:1.55;text-align:justify">'
          '<b>Historia disponible del grupo.</b> ${_nl(hd)}</p>');
    }
    if (pr.isNotEmpty) {
      b.write('<p style="font-size:11px;line-height:1.55;text-align:justify">'
          '<b>Criterio de logro del curso.</b> ${_nl(pr)}</p>');
    }
  }

  // (4-oct-2026) El proyecto que atraviesa el curso.
  final py = Map<String, dynamic>.from((planeacion['proyecto'] as Map?) ?? {});
  if (py['hay'] == true) {
    b.write(_h2('PROYECTO QUE ATRAVIESA EL CURSO'));
    b.write('<p style="font-size:11px;line-height:1.55;text-align:justify"><b>${_esc(py['nombre'])}.</b> ${_nl(_txt(py, 'queEs'))}</p>');
    if (_txt(py, 'condicionDesligamiento').isNotEmpty) {
      b.write('<p style="font-size:11px;line-height:1.55;text-align:justify"><b>Lo que el estudiante trae de su práctica.</b> ${_nl(_txt(py, 'condicionDesligamiento'))}</p>');
    }
    if (_txt(py, 'productoFinal').isNotEmpty) {
      b.write('<p style="font-size:11px;line-height:1.55;text-align:justify"><b>Producto final.</b> ${_nl(_txt(py, 'productoFinal'))}</p>');
    }
    final hitos = _comoListaMapas(py['hitos']);
    if (hitos.isNotEmpty) {
      b.write('<table style="width:100%;border-collapse:collapse;font-size:10.5px;margin-bottom:10px">'
          '<tr><th style="background:#B8842C;color:#fff;padding:5px 8px;text-align:left;width:50px">Sesión</th>'
          '<th style="background:#B8842C;color:#fff;padding:5px 8px;text-align:left">Avance del proyecto</th>'
          '<th style="background:#B8842C;color:#fff;padding:5px 8px;text-align:left">Evidencia</th></tr>');
      for (final h in hitos) {
        b.write('<tr><td style="border:1px solid #EFE9DC;padding:5px 8px;text-align:center">${h['sesion'] ?? ''}</td>'
            '<td style="border:1px solid #EFE9DC;padding:5px 8px">${_esc(h['avance'])}</td>'
            '<td style="border:1px solid #EFE9DC;padding:5px 8px">${_esc(h['evidencia'])}</td></tr>');
      }
      b.write('</table>');
    }
    if (_txt(py, 'relacionConProductos').isNotEmpty) {
      b.write('<p style="font-size:10.5px;color:#6B6257">${_esc(py['relacionConProductos'])}</p>');
    }
    final lb = _comoListaMapas(py['lecturasBase']);
    if (lb.isNotEmpty) {
      b.write('<p style="font-size:10.5px;color:#8A5F10"><b>Lecturas base del proyecto:</b> '
          '${lb.map((l) => '${_esc(l['ref'])}${_txt(l, 'paginas').isNotEmpty ? ' (${_esc(l['paginas'])})' : ''}').join('; ')}</p>');
    }
  }

  final dosi = _comoListaMapas(planeacion['dosificacion']);
  if (dosi.isNotEmpty) {
    b.write(_h2('DOSIFICACIÓN'));
    b.write('<table style="width:100%;border-collapse:collapse;font-size:10.5px;margin-bottom:14px">'
        '<tr>'
        '<th style="background:#1F1A17;color:#fff;padding:5px 8px;text-align:left;width:50px">Sesión</th>'
        '<th style="background:#1F1A17;color:#fff;padding:5px 8px;text-align:left">Tema</th>'
        '<th style="background:#1F1A17;color:#fff;padding:5px 8px;text-align:left">Propósito de la sesión</th>'
        '<th style="background:#1F1A17;color:#fff;padding:5px 8px;width:46px">Nivel</th></tr>');
    for (final x in dosi) {
      b.write('<tr>'
          '<td style="border:1px solid #EFE9DC;padding:5px 8px;text-align:center">${x['sesion'] ?? ''}'
          // (28-sep) El tipo de sesión: en Maestría en Educación hay asincrónicas.
          '${'${x['tipo'] ?? ''}'.isNotEmpty ? '<br><span style="font-size:8.5px;color:#6B6257">${_esc(x['tipo'])}</span>' : ''}</td>'
          '<td style="border:1px solid #EFE9DC;padding:5px 8px">${_esc(x['tema'])}'
          // (4-oct-2026) Las lecturas de la fila, con páginas; y el aviso si ningún texto del docente cubre el tema.
          '${_comoListaMapas(x['lecturas']).map((l) => '<br><span style="font-size:9px;color:#8A5F10">📖 ${_esc(l['ref'])}${_txt(l, 'paginas').isNotEmpty ? ' · ${_esc(l['paginas'])}' : ''}${_txt(l, 'para').isNotEmpty ? ' — ${_esc(l['para'])}' : ''}</span>').join()}'
          '${x['sinLiteraturaDelDocente'] == true ? '<br><span style="font-size:8.5px;color:#8E141D">Lectura propuesta por la IA: ningún texto del docente cubre este tema.</span>' : ''}</td>'
          '<td style="border:1px solid #EFE9DC;padding:5px 8px">${_esc(x['proposito'])}</td>'
          '<td style="border:1px solid #EFE9DC;padding:5px 8px;text-align:center">'
          '${(x['nivel'] ?? 0) == 0 ? '' : x['nivel']}</td></tr>');
    }
    b.write('</table>');
  }

  final sesiones = _comoListaMapas(planeacion['sesiones']);
  if (sesiones.isNotEmpty) {
    b.write(_h2('DESARROLLO DE LAS SESIONES'));
    for (var i = 0; i < sesiones.length; i++) {
      final n = int.tryParse('${sesiones[i]['sesion']}') ?? (i + 1);
      b.write(_fichaSesion(sesiones[i], n, plantilla: false));
    }
  }

  final acts = _comoListaMapas(planeacion['actividades']);
  if (acts.isNotEmpty) {
    b.write(_h2('PRODUCTOS DE APRENDIZAJE Y EVALUACIÓN'));
    b.write('<table style="width:100%;border-collapse:collapse;font-size:10.5px;margin-bottom:10px">'
        '<tr>'
        '<th style="background:#1F1A17;color:#fff;padding:5px 8px;text-align:left;width:26px">#</th>'
        '<th style="background:#1F1A17;color:#fff;padding:5px 8px;text-align:left">Producto</th>'
        '<th style="background:#1F1A17;color:#fff;padding:5px 8px;text-align:left">Criterio de desempeño</th>'
        '<th style="background:#1F1A17;color:#fff;padding:5px 8px;width:40px">Nivel</th>'
        '<th style="background:#1F1A17;color:#fff;padding:5px 8px;width:40px">%</th></tr>');
    for (final a in acts) {
      final desc = _txt(a, 'descripcion');
      b.write('<tr>'
          '<td style="border:1px solid #EFE9DC;padding:5px 8px;text-align:center">${a['numero'] ?? ''}</td>'
          '<td style="border:1px solid #EFE9DC;padding:5px 8px"><b>${_esc(a['nombre'])}</b>'
          '${a['esDelProyecto'] == true ? ' <span style="font-size:8.5px;color:#8A5F10;font-weight:bold">· ENTREGA DEL PROYECTO</span>' : ''}'
          '${desc.isNotEmpty ? '<br><span style="font-size:9.5px;color:#6B6257">${_esc(desc)}</span>' : ''}'
          '${_comoListaMapas(a['lecturasBase']).map((l) => '<br><span style="font-size:9px;color:#8A5F10">📖 ${_esc(l['ref'])}${_txt(l, 'paginas').isNotEmpty ? ' · ${_esc(l['paginas'])}' : ''}</span>').join()}</td>'
          '<td style="border:1px solid #EFE9DC;padding:5px 8px">${_esc(a['criterioDesempeno'])}</td>'
          '<td style="border:1px solid #EFE9DC;padding:5px 8px;text-align:center">'
          '${(a['nivel'] ?? 0) == 0 ? '' : a['nivel']}</td>'
          '<td style="border:1px solid #EFE9DC;padding:5px 8px;text-align:center">${a['ponderacion'] ?? ''}</td></tr>');
    }
    b.write('</table>');
    final ev = Map<String, dynamic>.from((planeacion['evaluacion'] as Map?) ?? {});
    if (_txt(ev, 'escala').isNotEmpty) {
      b.write('<p style="font-size:10.5px;color:#6B6257"><b>Escala.</b> ${_esc(ev['escala'])}</p>');
    }
    if (_txt(ev, 'comoSeSustenta').isNotEmpty) {
      b.write('<p style="font-size:10.5px;color:#6B6257">${_esc(ev['comoSeSustenta'])}</p>');
    }
  }

  final bib = _comoListaMapas(planeacion['bibliografia']);
  if (bib.isNotEmpty) {
    b.write(_h2('BIBLIOGRAFÍA'));
    b.write('<div style="font-size:10.5px;line-height:1.55">');
    for (final x in bib) {
      b.write('<div style="margin-bottom:5px;padding-left:20px;text-indent:-20px">'
          '${_esc(x['cita'])}'
          '${x['de'] == 'docente' ? ' <span style="color:#8A5F10;font-size:9px">[literatura del docente]</span>' : ''}'
          '${x['verificar'] == true ? ' <span style="color:#8E141D;font-size:9px">[por verificar]</span>' : ''}'
          '</div>');
    }
    b.write('</div>');
  }

  b.write(_firmas(docente.isNotEmpty ? docente : _txt(c, 'docente'), modeloVersion, false));
  return b.toString();
}

/// La plantilla en blanco, precargada con los datos curriculares y con una
/// ficha por cada sesión que el curso realmente tiene. Para el docente que
/// prefiere planear él mismo: no arranca de una hoja vacía ni captura lo
/// que la institución ya sabe.
String documentoPlantilla({
  required Map<String, dynamic> contexto,
  String docente = '',
}) {
  final c = Map<String, dynamic>.from((contexto['curricular'] as Map?) ?? {});
  final d = Map<String, dynamic>.from((contexto['dosificacion'] as Map?) ?? {});
  final nSes = int.tryParse('${d['sesiones'] ?? 5}') ?? 5;

  final b = StringBuffer();
  b.write(_cabecera());
  b.write(_fichaCurricular(c, d, docente));
  b.write(_finesYTemario(c));

  b.write(_h2('ENCUADRE DIDÁCTICO'));
  b.write('<table style="width:100%;border-collapse:collapse;margin-bottom:14px">'
      '<tr><td style="background:#FBF7EF;color:#B8842C;font-weight:bold;font-size:10px;'
      'padding:6px 10px;border:1px solid #EADFCB;width:170px">Análisis funcional del propósito</td>'
      '<td style="border:1px solid #EADFCB;padding:6px 10px"><div style="min-height:44px"></div></td></tr>'
      '<tr><td style="background:#FBF7EF;color:#B8842C;font-weight:bold;font-size:10px;'
      'padding:6px 10px;border:1px solid #EADFCB">Nivel meta del curso</td>'
      '<td style="border:1px solid #EADFCB;padding:6px 10px;font-size:10px;color:#999">'
      '1 contextual · 2 suplementario · 3 selector · <b>4 sustitutivo referencial</b> · '
      '<b>5 sustitutivo no referencial</b> (4 y 5 son las complejas)</td></tr>'
      '<tr><td style="background:#FBF7EF;color:#B8842C;font-weight:bold;font-size:10px;'
      'padding:6px 10px;border:1px solid #EADFCB">Historia disponible del grupo</td>'
      '<td style="border:1px solid #EADFCB;padding:6px 10px"><div style="min-height:34px"></div></td></tr>'
      '<tr><td style="background:#FBF7EF;color:#B8842C;font-weight:bold;font-size:10px;'
      'padding:6px 10px;border:1px solid #EADFCB">Criterio de logro del curso</td>'
      '<td style="border:1px solid #EADFCB;padding:6px 10px"><div style="min-height:34px"></div>'
      '<div style="font-size:9px;color:#999">Se escribe con el verbo del ALUMNO y es observable. '
      'No «que comprendan».</div></td></tr></table>');

  b.write(_h2('DOSIFICACIÓN'));
  b.write('<table style="width:100%;border-collapse:collapse;font-size:10.5px;margin-bottom:14px">'
      '<tr><th style="background:#1F1A17;color:#fff;padding:5px 8px;width:50px">Sesión</th>'
      '<th style="background:#1F1A17;color:#fff;padding:5px 8px;text-align:left">Tema</th>'
      '<th style="background:#1F1A17;color:#fff;padding:5px 8px;text-align:left">Propósito de la sesión</th>'
      '<th style="background:#1F1A17;color:#fff;padding:5px 8px;width:46px">Nivel</th></tr>');
  for (var i = 1; i <= nSes; i++) {
    b.write('<tr><td style="border:1px solid #EFE9DC;padding:8px;text-align:center">$i</td>'
        '<td style="border:1px solid #EFE9DC;padding:8px"></td>'
        '<td style="border:1px solid #EFE9DC;padding:8px"></td>'
        '<td style="border:1px solid #EFE9DC;padding:8px"></td></tr>');
  }
  b.write('</table>');

  b.write(_h2('DESARROLLO DE LAS SESIONES'));
  for (var i = 1; i <= nSes; i++) {
    b.write(_fichaSesion(
        {'inicio': {}, 'desarrollo': {}, 'cierre': {}, 'recursos': []}, i,
        plantilla: true));
  }

  b.write(_h2('PRODUCTOS DE APRENDIZAJE Y EVALUACIÓN'));
  b.write('<table style="width:100%;border-collapse:collapse;font-size:10.5px;margin-bottom:8px">'
      '<tr><th style="background:#1F1A17;color:#fff;padding:5px 8px;width:26px">#</th>'
      '<th style="background:#1F1A17;color:#fff;padding:5px 8px;text-align:left">Producto</th>'
      '<th style="background:#1F1A17;color:#fff;padding:5px 8px;text-align:left">Criterio de desempeño</th>'
      '<th style="background:#1F1A17;color:#fff;padding:5px 8px;width:40px">Nivel</th>'
      '<th style="background:#1F1A17;color:#fff;padding:5px 8px;width:40px">%</th></tr>');
  for (var i = 1; i <= 5; i++) {
    b.write('<tr><td style="border:1px solid #EFE9DC;padding:9px;text-align:center">$i</td>'
        '<td style="border:1px solid #EFE9DC;padding:9px"></td>'
        '<td style="border:1px solid #EFE9DC;padding:9px"></td>'
        '<td style="border:1px solid #EFE9DC;padding:9px"></td>'
        '<td style="border:1px solid #EFE9DC;padding:9px"></td></tr>');
  }
  b.write('<tr><td colspan="4" style="border:1px solid #EFE9DC;padding:6px 9px;'
      'text-align:right;font-weight:bold">Total</td>'
      '<td style="border:1px solid #EFE9DC;padding:6px 9px;text-align:center;font-weight:bold">100</td></tr>'
      '</table>'
      '<p style="font-size:10px;color:#6B6257">Entre 3 y 6 productos, idealmente uno por semana, '
      'todos con cierre el domingo de la última semana. Escala 0 a 100 con rúbrica; acta de 6 a 10 '
      'entero; entregas extemporáneas a 80 máximo. La asistencia a las sesiones no es criterio de '
      'evaluación.</p>');

  b.write(_h2('BIBLIOGRAFÍA'));
  b.write('<div style="border:1px solid #EADFCB;min-height:110px"></div>');

  b.write(_firmas(docente.isNotEmpty ? docente : _txt(c, 'docente'), '', true));
  return b.toString();
}

// ── Descarga ────────────────────────────────────────────────────────
String _nombreArchivo(Map<String, dynamic> contexto, String ext, bool plantilla) {
  final c = Map<String, dynamic>.from((contexto['curricular'] as Map?) ?? {});
  var n = _txt(c, 'denominacion');
  if (n.isEmpty) n = 'Planeacion';
  n = n.replaceAll(RegExp(r'[^\wáéíóúñÁÉÍÓÚÑ ]'), '').replaceAll(RegExp(r'\s+'), '_');
  if (n.length > 55) n = n.substring(0, 55);
  return 'CESSUM_Planeacion_${plantilla ? 'PLANTILLA_' : ''}$n.$ext';
}

/// Word. El mismo HTML envuelto con la cabecera que Word reconoce; se
/// descarga como Blob, igual que el CSV de grupos.
void descargarWord(String cuerpo, Map<String, dynamic> contexto, {bool plantilla = false}) {
  final doc = '<html xmlns:o="urn:schemas-microsoft-com:office:office" '
      'xmlns:w="urn:schemas-microsoft-com:office:word">'
      '<head><meta charset="utf-8">'
      '<!--[if gte mso 9]><xml><w:WordDocument><w:View>Print</w:View></w:WordDocument></xml><![endif]-->'
      '<style>@page{size:21.6cm 27.9cm;margin:2cm}'
      'body{font-family:$_kSans;font-size:11px;color:#1F1A17}h2{font-family:$_kTit}</style>$_kFuentes</head>'
      '<body>$cuerpo</body></html>';
  final bytes = utf8.encode('\uFEFF$doc'); // BOM: los acentos salen bien en Word
  final blob = html.Blob(<dynamic>[bytes], 'application/msword');
  final url = html.Url.createObjectUrlFromBlob(blob);
  // (2-oct) El enlace se agrega al documento y la URL se libera DESPUÉS: Firefox exige que el enlace esté en la
  // página para que click() descargue, y liberar la URL en el mismo instante cancelaba la descarga en algunos navegadores.
  final enlace = html.AnchorElement(href: url)
    ..setAttribute('download', _nombreArchivo(contexto, 'doc', plantilla))
    ..style.display = 'none';
  html.document.body!.append(enlace);
  enlace.click();
  Future.delayed(const Duration(seconds: 10), () {
    try {
      enlace.remove();
    } catch (_) {}
    html.Url.revokeObjectUrl(url);
  });
}

// ── PDF ─────────────────────────────────────────────────────────────
/// (2-oct) El documento usa FONDOS DE COLOR (encabezados de tabla y título de cada sesión en texto blanco sobre fondo oscuro,
/// barras rojas y doradas, celdas sombreadas). Los navegadores NO imprimen fondos por defecto: el PDF salía con el texto blanco
/// sobre papel blanco (invisible) y sin barras. Estas reglas obligan a imprimirlos tal como se ven en pantalla.
const String _kCssImpresion = '*{-webkit-print-color-adjust:exact !important;print-color-adjust:exact !important;'
    'color-adjust:exact !important}'
    '@page{size:letter;margin:1.6cm}'
    'body{font-family:$_kSans;font-size:11px;color:#1F1A17;margin:0}'
    '.cessum-marca{position:fixed;right:-30px;bottom:-30px;width:260px;opacity:.045;z-index:-1}'
    'h2{page-break-after:avoid}';

String _docImpresion(String cuerpo, Map<String, dynamic> contexto, bool plantilla, {String extra = ''}) {
  // El navegador propone el título como nombre del archivo: sin la extensión, para que no salga «.pdf.pdf».
  final titulo = _nombreArchivo(contexto, 'pdf', plantilla).replaceAll(RegExp(r'\.pdf$'), '');
  return '<!doctype html><html><head><meta charset="utf-8">'
      '<title>${_esc(titulo)}</title>$_kFuentes<style>$_kCssImpresion</style></head>'
      '<body><img class="cessum-marca" src="$_kIsotipo" alt="">$cuerpo$extra</body></html>';
}

/// El marco oculto imprime bien en Chrome, Edge y Firefox de escritorio. En celulares y en Safari NO: ahí se usa una pestaña.
bool _imprimeDesdeMarco() {
  final ua = html.window.navigator.userAgent;
  final movil = RegExp(r'Android|iPhone|iPad|iPod|Mobile', caseSensitive: false).hasMatch(ua);
  final safari = ua.contains('Safari') && !RegExp(r'Chrome|Chromium|CriOS|Edg|Firefox|FxiOS|OPR').hasMatch(ua);
  return !movil && !safari;
}

/// Abre el documento en una pestaña y lo imprime solo al cargar. Devuelve false si el navegador bloqueó la ventana.
bool _imprimirEnPestana(String cuerpo, Map<String, dynamic> contexto, bool plantilla) {
  final doc = _docImpresion(cuerpo, contexto, plantilla,
      extra: '<script>window.addEventListener("load",function(){setTimeout(function(){window.focus();window.print();},700);});</script>');
  final url = html.Url.createObjectUrlFromBlob(html.Blob(<dynamic>[doc], 'text/html'));
  try {
    final dynamic ventana = html.window.open(url, '_blank');
    Future.delayed(const Duration(minutes: 2), () => html.Url.revokeObjectUrl(url));
    return ventana != null;
  } catch (_) {
    return false; // ventana emergente bloqueada
  }
}

/// Espera a que carguen las imágenes del marco (el logotipo); si no, el PDF sale sin ellas. Nunca lanza.
Future<void> _esperarImagenes(dynamic ventana, Duration limite) async {
  try {
    final fin = DateTime.now().add(limite);
    while (DateTime.now().isBefore(fin)) {
      final dynamic imagenes = ventana.document.querySelectorAll('img');
      var pendientes = 0;
      for (final dynamic img in imagenes) {
        if (img.complete == false) pendientes++;
      }
      if (pendientes == 0) return;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  } catch (_) {
    await Future<void>.delayed(const Duration(milliseconds: 900));
  }
}

/// PDF. Devuelve true si se abrió la ventana de impresión (donde se elige «Guardar como PDF») y false si el navegador bloqueó la
/// ventana emergente, para que la pantalla lo avise (antes un fallo no decía nada).
///  · Escritorio (Chrome, Edge, Firefox): marco oculto con tamaño real fuera de pantalla — a 0×0 el navegador podía imprimir en blanco.
///  · Celular y Safari: pestaña con impresión automática.
///  · Si el marco no carga en 3 s o no puede imprimir, se usa la pestaña.
bool imprimirPdf(String cuerpo, Map<String, dynamic> contexto, {bool plantilla = false}) {
  if (!_imprimeDesdeMarco()) return _imprimirEnPestana(cuerpo, contexto, plantilla);

  final marco = html.IFrameElement()
    ..style.position = 'fixed'
    ..style.left = '-10000px'
    ..style.top = '0'
    ..style.width = '816px' // carta a 96 dpi
    ..style.height = '1056px'
    ..style.border = '0'
    ..setAttribute('aria-hidden', 'true')
    ..setAttribute('tabindex', '-1');
  var atendido = false;
  marco.onLoad.listen((_) async {
    if (atendido) return;
    atendido = true;
    final dynamic ventana = marco.contentWindow;
    await _esperarImagenes(ventana, const Duration(seconds: 5));
    await Future<void>.delayed(const Duration(milliseconds: 150));
    try {
      ventana.focus();
      ventana.print();
    } catch (_) {
      _imprimirEnPestana(cuerpo, contexto, plantilla); // el marco no pudo imprimir
    }
    Future.delayed(const Duration(seconds: 90), () {
      try {
        marco.remove();
      } catch (_) {}
    });
  });
  // El contenido se asigna ANTES de insertar el marco: así el único «load» es el del documento y no el de una página en blanco.
  marco.srcdoc = _docImpresion(cuerpo, contexto, plantilla);
  html.document.body!.append(marco);
  // Si el marco nunca carga, no se queda en silencio.
  Future.delayed(const Duration(seconds: 3), () {
    if (atendido) return;
    atendido = true;
    try {
      marco.remove();
    } catch (_) {}
    _imprimirEnPestana(cuerpo, contexto, plantilla);
  });
  return true;
}

/// (3-oct-2026) LEER el documento en una pestaña nueva, SIN imprimir. Es lo que Vicerrectoría necesita para revisar una planeación
/// antes de dictaminarla: «PDF» abre el cuadro de impresión (para guardar), no una lectura. Devuelve false si el navegador bloqueó
/// la ventana emergente, para que la pantalla lo avise.
bool abrirDocumento(String cuerpo, Map<String, dynamic> contexto, {bool plantilla = false}) {
  final doc = _docImpresion(cuerpo, contexto, plantilla);
  final url = html.Url.createObjectUrlFromBlob(html.Blob(<dynamic>[doc], 'text/html'));
  try {
    final dynamic ventana = html.window.open(url, '_blank');
    Future.delayed(const Duration(minutes: 5), () => html.Url.revokeObjectUrl(url));
    return ventana != null;
  } catch (_) {
    return false; // ventana emergente bloqueada
  }
}

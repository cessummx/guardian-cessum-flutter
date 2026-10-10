// ============================================================
//  CENTRO DE DECISIONES  ·  (ago-27)
//  ------------------------------------------------------------
//  QUÉ LO SEPARA DE «SALUD DE DATOS»
//  Salud de datos enumera lo que está mal. Esta pantalla dice QUÉ HACER y,
//  sobre todo, QUÉ PASA SI NO SE HACE. Un tablero que dice «11 correos
//  duplicados» se mira una vez y se ignora; uno que dice «dos alumnas
//  comparten acceso y una puede ver las calificaciones de la otra» se atiende
//  hoy.
//
//  EL ORDEN ES POR DAÑO, NO POR CANTIDAD
//  Un solo caso que expone datos de una persona a otra va antes que treinta
//  grupos sin aula. Ordenar por conteo, que es lo natural al programar, pone
//  lo urgente al final.
//
//  EL PROMPT
//  Cuando un hallazgo no se resuelve desde ninguna pantalla, el botón arma un
//  texto listo para pegar en Claude, con el problema estructural y los
//  identificadores mínimos para reproducirlo — NUNCA nombres, correos ni
//  teléfonos. Un prompt con el expediente sería sacar datos personales del
//  sistema para pegarlos en un chat.
// ============================================================

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

class DecisionesScreen extends StatefulWidget {
  final String actor;
  const DecisionesScreen({super.key, required this.actor});

  @override
  State<DecisionesScreen> createState() => _DecisionesScreenState();
}

class _DecisionesScreenState extends State<DecisionesScreen> {
  bool _cargando = true;
  String _error = '';
  Map<String, dynamic> _d = {};
  final Set<String> _atendidos = {};

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = '';
    });
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'decisiones',
        'actor': widget.actor,
      });
      final r = await http.get(uri).timeout(const Duration(seconds: 120));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _d = d;
        if (d['ok'] != true) _error = '${d['error'] ?? 'No se pudo consultar.'}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo consultar. El diagnóstico recorre varias hojas y '
            'puede tardar; vuelve a intentarlo.';
      });
    }
  }

  Color _colorDe(String g) {
    switch (g) {
      case 'critico':
        return cessumRed;
      case 'alto':
        return Colors.orange.shade800;
      case 'medio':
        return cessumGold;
      default:
        return Colors.grey.shade600;
    }
  }

  String _etiquetaDe(String g) {
    switch (g) {
      case 'critico':
        return 'CRÍTICO';
      case 'alto':
        return 'ALTO';
      case 'medio':
        return 'MEDIO';
      default:
        return 'BAJO';
    }
  }

  /// Arma el prompt de un hallazgo y lo deja en el portapapeles.
  ///
  /// Lleva el problema, su consecuencia, dónde vive el dato y qué se ha
  /// intentado. NO lleva nombres, correos ni teléfonos: con la matrícula y el
  /// programa se puede reproducir el caso sin exponer a nadie.
  Future<void> _copiarPrompt(Map<String, dynamic> h) async {
    final ejemplos = (h['ejemplos'] as List?) ?? [];
    final buf = StringBuffer();

    buf.writeln('Contexto: sistema Guardián de CESSUM (Google Apps Script + '
        'Flutter web). Necesito resolver un problema de datos que el Centro de '
        'Decisiones marcó y que no se puede corregir desde ninguna pantalla '
        'actual.');
    buf.writeln();
    buf.writeln('PROBLEMA: ${h['titulo']}');
    buf.writeln('Casos detectados: ${h['cuantos']}');
    buf.writeln('Gravedad: ${_etiquetaDe('${h['gravedad']}')} · '
        'Ámbito: ${h['ambito']}');
    buf.writeln();
    buf.writeln('POR QUÉ IMPORTA:');
    buf.writeln('${h['consecuencia']}');
    buf.writeln();
    buf.writeln('SI NO SE ATIENDE:');
    buf.writeln('${h['siNoSeHace']}');
    buf.writeln();
    buf.writeln('DÓNDE VIVE EL DATO: ${h['resuelveEn']}');
    buf.writeln('CÓMO SE RESUELVE HOY (a mano): ${h['comoSeResuelve']}');
    buf.writeln();

    if (ejemplos.isNotEmpty) {
      buf.writeln('EJEMPLOS (sin datos personales, solo identificadores):');
      for (final e in ejemplos) {
        buf.writeln('· ${jsonEncode(e)}');
      }
      buf.writeln();
    }

    buf.writeln('LO QUE NECESITO:');
    buf.writeln('1. Una ruta en Code.gs que detecte todos los casos y los '
        'devuelva con el dato suficiente para decidir uno por uno.');
    buf.writeln('2. Si la corrección se puede automatizar sin riesgo, que la '
        'aplique — SIEMPRE con modo de prueba primero (&prueba=1) que muestre '
        'qué haría sin tocar nada.');
    buf.writeln('3. Si toca datos de personas, respaldo íntegro antes de '
        'modificar y bitácora de quién lo corrió.');
    buf.writeln('4. La pantalla para resolverlos caso por caso, con el '
        'contexto a la vista para no decidir a ciegas.');
    buf.writeln();
    buf.writeln('Cuidados: no inventes claves ni matrículas; si un dato falta, '
        'dilo en vez de suponerlo. Y avísame antes de cualquier corrida que '
        'escriba en las hojas o mande correos.');

    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('Prompt copiado. Pégalo en Claude para que construya '
          'la solución.'),
      backgroundColor: Colors.green.shade700,
      duration: const Duration(seconds: 5),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final hallazgos = ((_d['hallazgos'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Centro de decisiones',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Volver a diagnosticar',
            onPressed: _cargando ? null : _cargar,
          ),
        ],
      ),
      body: _cargando
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: cessumRed),
                  SizedBox(height: 14),
                  Text('Revisando el padrón, las asignaciones y las '
                      'calificaciones…',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13)),
                ],
              ),
            )
          : _error.isNotEmpty
              ? _pantallaError()
              : (hallazgos.isEmpty ? _sinHallazgos() : _lista(hallazgos)),
    );
  }

  Widget _pantallaError() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.error_outline, size: 40, color: cessumRed),
            const SizedBox(height: 12),
            Text(_error, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: _cargar, child: const Text('Reintentar')),
          ]),
        ),
      );

  Widget _sinHallazgos() => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.verified_outlined, size: 44, color: Colors.green.shade600),
            const SizedBox(height: 14),
            const Text('Sin hallazgos que decidir',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              '${_d['nota'] ?? ''}',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: cessumMuted(context)),
            ),
          ]),
        ),
      );

  Widget _lista(List<Map<String, dynamic>> hallazgos) {
    final criticos = (_d['criticos'] as num?)?.toInt() ?? 0;
    final erroresLectura = (_d['erroresDeLectura'] as List?) ?? [];

    return RefreshIndicator(
      color: cessumRed,
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Lo primero: qué atender hoy si solo hubiera tiempo para una cosa.
          if ('${_d['primero'] ?? ''}'.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: criticos > 0
                    ? cessumRed.withValues(alpha: 0.07)
                    : cessumGold.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(13),
                border: Border(
                  left: BorderSide(
                      color: criticos > 0 ? cessumRed : cessumGold, width: 4),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    criticos > 0
                        ? 'Si hoy solo alcanza para una cosa'
                        : 'Por dónde empezar',
                    style: TextStyle(
                        fontSize: 11.5,
                        letterSpacing: 0.6,
                        fontWeight: FontWeight.w800,
                        color: criticos > 0 ? cessumRed : cessumGold),
                  ),
                  const SizedBox(height: 4),
                  Text('${_d['primero']}',
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(
                    '${_d['tipos'] ?? 0} tipo(s) de hallazgo · '
                    '${_d['casosTotales'] ?? 0} caso(s) en total'
                    '${criticos > 0 ? ' · $criticos crítico(s)' : ''}',
                    style: TextStyle(
                        fontSize: 12.5, color: cessumMuted(context)),
                  ),
                ],
              ),
            ),

          if (erroresLectura.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Ojo: ${erroresLectura.length} diagnóstico(s) no respondieron, '
                'así que este tablero puede estar incompleto. No es que no haya '
                'hallazgos ahí: es que no se pudieron leer.',
                style: const TextStyle(fontSize: 12.5, height: 1.4),
              ),
            ),
          ],

          const SizedBox(height: 18),
          ...hallazgos.map(_tarjeta),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _tarjeta(Map<String, dynamic> h) {
    final id = '${h['id'] ?? ''}';
    final grav = '${h['gravedad'] ?? ''}';
    final color = _colorDe(grav);
    final atendido = _atendidos.contains(id);
    final ejemplos = (h['ejemplos'] as List?) ?? [];

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(13),
        side: BorderSide(
            color: atendido
                ? Colors.green.withValues(alpha: 0.4)
                : color.withValues(alpha: 0.3)),
      ),
      color: atendido ? Colors.green.withValues(alpha: 0.04) : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: color, borderRadius: BorderRadius.circular(20)),
                child: Text(_etiquetaDe(grav),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5)),
              ),
              const SizedBox(width: 8),
              Text('${h['ambito'] ?? ''}',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: cessumMuted(context))),
              const Spacer(),
              Text('${h['cuantos'] ?? 0}',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: color)),
            ]),
            const SizedBox(height: 8),
            Text('${h['titulo'] ?? ''}',
                style: const TextStyle(
                    fontSize: 16.5, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),

            // La consecuencia primero: es lo que hace que se atienda.
            Text('${h['consecuencia'] ?? ''}',
                style: const TextStyle(fontSize: 13.5, height: 1.5)),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded, size: 16, color: color),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text('Si no se atiende: ${h['siNoSeHace'] ?? ''}',
                        style: TextStyle(
                            fontSize: 12.5,
                            height: 1.45,
                            fontWeight: FontWeight.w600,
                            color: color)),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),
            _dato('Dónde se corrige', '${h['resuelveEn'] ?? ''}'),
            const SizedBox(height: 6),
            _dato('Cómo', '${h['comoSeResuelve'] ?? ''}'),

            if (ejemplos.isNotEmpty) ...[
              const SizedBox(height: 10),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 8),
                title: Text('Ver ${ejemplos.length} ejemplo(s)',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: cessumMuted(context))),
                children: ejemplos
                    .map((e) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: SelectableText('· ${jsonEncode(e)}',
                              style: const TextStyle(
                                  fontSize: 11.5, height: 1.4)),
                        ))
                    .toList(),
              ),
            ],

            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              // Si hay corrida automática, se ofrece SIEMPRE en modo prueba:
              // nunca un botón que escriba en las hojas de un clic.
              if (h['automatizable'] == true && '${h['ruta'] ?? ''}'.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () => _verRuta('${h['ruta']}'),
                  icon: const Icon(Icons.play_circle_outline, size: 17),
                  label: const Text('Ver qué haría (sin aplicar)'),
                  style: OutlinedButton.styleFrom(foregroundColor: cessumGold),
                ),
              // El prompt: para lo que no se resuelve desde ninguna pantalla.
              ElevatedButton.icon(
                onPressed: () => _copiarPrompt(h),
                icon: const Icon(Icons.content_copy, size: 16),
                label: const Text('Copiar prompt para Claude'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed,
                  foregroundColor: Colors.white,
                ),
              ),
              TextButton.icon(
                onPressed: () => setState(() {
                  if (atendido) {
                    _atendidos.remove(id);
                  } else {
                    _atendidos.add(id);
                  }
                }),
                icon: Icon(
                    atendido ? Icons.undo : Icons.check_circle_outline,
                    size: 17),
                label: Text(atendido ? 'Quitar marca' : 'Ya lo atendí'),
                style: TextButton.styleFrom(
                    foregroundColor:
                        atendido ? Colors.grey : Colors.green.shade700),
              ),
            ]),
            if (atendido)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Marcado como atendido en esta sesión. Vuelve a '
                  'diagnosticar para confirmar que ya no aparece.',
                  style: TextStyle(
                      fontSize: 11.5, color: cessumMuted(context)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _dato(String etiqueta, String valor) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(etiqueta.toUpperCase(),
              style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 0.5,
                  fontWeight: FontWeight.w800,
                  color: cessumMuted(context))),
          Text(valor, style: const TextStyle(fontSize: 13, height: 1.45)),
        ],
      );

  void _verRuta(String ruta) {
    final url = '$guardianUrl?$ruta&actor=${Uri.encodeComponent(widget.actor)}';
    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('Enlace copiado. Ábrelo en el navegador: es modo de '
          'prueba, muestra qué haría sin tocar nada.'),
      backgroundColor: cessumGold,
      duration: const Duration(seconds: 6),
    ));
  }
}

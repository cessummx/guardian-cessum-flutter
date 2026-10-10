// ADMIN · CENTRO SIGA: panel para generar y descargar los exportables al SIGA
// (autoridad educativa), y la tabla de equivalencias generación → ciclo escolar
// + carga (que resuelve ciclo_escolar/no_carga y habilita el filtro por ciclo).
// Cada exportable muestra su estado (registros, errores) con claridad antes de
// descargar el Excel (hoja Datos + Ayuda, formato SIGA).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';
import 'package:url_launcher/url_launcher.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'siga_diagnostico_screen.dart';
import 'siga_bitacora_screen.dart';

class SigaEquivalenciasScreen extends StatefulWidget {
  const SigaEquivalenciasScreen({super.key});

  @override
  State<SigaEquivalenciasScreen> createState() =>
      _SigaEquivalenciasScreenState();
}

// Definición de cada exportable SIGA: título, acción de datos y de excel.
class _FormatoSiga {
  final String clave;
  final String titulo;
  final String descripcion;
  final IconData icono;
  final String accionDatos; // ?accion= que devuelve total/conError
  final String accionExcel; // ?accion= que genera el xlsx
  final bool disponible; // false = aún depende de captura (ciclo, etc.)
  final bool requiereEquiv; // true = se habilita cuando hay equivalencias
  final String? nota; // por qué no está disponible / advertencia
  const _FormatoSiga(this.clave, this.titulo, this.descripcion, this.icono,
      this.accionDatos, this.accionExcel,
      {this.disponible = true, this.requiereEquiv = false, this.nota});
}

const List<_FormatoSiga> _formatos = [
  _FormatoSiga(
    'alumnos', 'Alumnos', 'Padrón de estudiantes con CURP y situación',
    Icons.people_alt, 'siga_alumnos', 'siga_alumnos_excel',
  ),
  _FormatoSiga(
    'oferta', 'Oferta educativa', 'Materias del plan por programa',
    Icons.menu_book, 'siga_oferta', 'siga_oferta_excel',
  ),
  _FormatoSiga(
    'docentes', 'Docentes', 'Padrón de profesores con CURP y escolaridad',
    Icons.co_present, 'siga_docentes', 'siga_docentes_excel',
    nota: 'Captura la CURP de cada docente en la pantalla de Profesores.',
  ),
  _FormatoSiga(
    'carga', 'Carga horaria', 'Alumno-materia-grupo por ciclo',
    Icons.schedule, 'siga_carga', 'siga_carga_excel',
    requiereEquiv: true,
    nota: 'Requiere equivalencias (ciclo por generación) capturadas.',
  ),
  _FormatoSiga(
    'calif', 'Calificaciones', 'Calificación por alumno y materia',
    Icons.grade, 'siga_calif', 'siga_calif_excel',
    requiereEquiv: true,
    nota: 'Requiere equivalencias capturadas y CURP de docentes.',
  ),
];

class _SigaEquivalenciasScreenState extends State<SigaEquivalenciasScreen> {
  // (23-sep) SIGA cerrado: toda dirección del Guardián lleva el correo de
  // quien consulta. Se obtiene una sola vez.
  String _yo = '';
  Future<String> _actorQ() async {
    if (_yo.isEmpty) _yo = ((await SessionStore.realEmail()) ?? '').trim().toLowerCase();
    return 'actor=${Uri.encodeQueryComponent(_yo)}&';
  }

  // Estado de cada formato: {total, conError, cargando}
  final Map<String, Map<String, dynamic>> _estado = {};
  // Ciclos disponibles (de equivalencias) y el elegido para exportar.
  List<Map<String, dynamic>> _ciclos = [];
  String? _cicloSel; // formato "2026-2027|2"
  // Materias sin periodo (para capturar override).
  List<Map<String, dynamic>> _periodoFaltante = [];
  // Equivalencias
  List<Map<String, dynamic>> _lista = [];
  bool _cargandoEquiv = true;
  String _busqueda = '';
  bool _soloPendientes = false;

  @override
  void initState() {
    super.initState();
    // (23-sep) Solo lo suyo: equivalencias y periodos. Ya no calcula los cinco
    // formatos al abrirse: los archivos se generan en la Cabina SIGA.
    _cargarEquivalencias();
    _cargarPeriodoFaltante();
  }

  Future<void> _cargarPeriodoFaltante() async {
    try {
      final resp = await http
          .get(Uri.parse('$guardianUrl?${await _actorQ()}accion=siga_periodo_faltante'))
          .timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _periodoFaltante = ((data['materias'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      });
    } catch (_) {}
  }

  Future<void> _cargarCiclos() async {
    try {
      final resp = await http
          .get(Uri.parse('$guardianUrl?${await _actorQ()}accion=siga_ciclos_listar'))
          .timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _ciclos = ((data['ciclos'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      });
    } catch (_) {}
  }

  // Sufijo de filtro para las URLs de exportación de carga/calificaciones.
  String get _filtroCiclo {
    if (_cicloSel == null) return '';
    final partes = _cicloSel!.split('|');
    final ciclo = partes[0];
    final carga = partes.length > 1 ? partes[1] : '';
    // (ago-19) FALTABAN LOS DOS FILTROS QUE HACEN QUE ESTO QUEPA EN EL TIEMPO.
    // Sin porFecha y soloCursando, Carga y Calificaciones recorren el
    // histórico completo —4,831 filas— y el proxy corta a los 120 s: de ahí
    // el «No se pudo consultar. Toca refrescar.». Con ellos son 746 filas del
    // ciclo real. Y no es solo velocidad: son los mismos filtros del reporte
    // que se entrega, así que el conteo de la pantalla y el del paquete por
    // fin dicen lo mismo.
    return '&ciclo=${Uri.encodeComponent(ciclo)}'
        '&carga=${Uri.encodeComponent(carga)}'
        '&porFecha=1&soloCursando=1';
  }

  // ¿Hay al menos una equivalencia capturada? (habilita carga/calif)
  bool get _hayEquivalencias =>
      _lista.any((e) => e['capturado'] == true);

  // Un formato está activo si es disponible y, de requerir equivalencias, ya hay.
  bool _formatoActivo(_FormatoSiga f) =>
      f.disponible && (!f.requiereEquiv || _hayEquivalencias);

  // Estado semáforo de un formato:
  //  'bloqueado' (gris) — falta captura previa (equivalencias/CURP)
  //  'cargando'         — consultando
  //  'error_consulta'   — no respondió
  //  'listo' (verde)    — tiene registros y 0 por corregir
  //  'pendiente' (ámbar)— tiene registros pero con datos por corregir
  //  'vacio' (gris)     — activo pero 0 registros (aún no hay datos)
  String _estadoSemaforo(_FormatoSiga f) {
    if (!_formatoActivo(f)) return 'bloqueado';
    final st = _estado[f.clave] ?? {};
    if (st['cargando'] == true) return 'cargando';
    if (st['error'] == true) return 'error_consulta';
    final total = st['total'];
    if (total == null) return 'cargando';
    if (total == 0) return 'vacio';
    final err = st['conError'] ?? 0;
    return err == 0 ? 'listo' : 'pendiente';
  }

  Color _colorSemaforo(String estado) {
    switch (estado) {
      case 'listo':
        return const Color(0xFF1E8E3E); // verde
      case 'pendiente':
        return const Color(0xFFB08D57); // ámbar/dorado
      case 'error_consulta':
        return Colors.red;
      case 'bloqueado':
      case 'vacio':
      case 'cargando':
      default:
        return Colors.grey;
    }
  }

  /// (ago-19, 2ª corrección) LA PANTALLA YA NO CUENTA LO PESADO AL ABRIR.
  ///
  /// Primero lo puse en fila y los dos pesados llegaban muertos. Después lo
  /// puse en paralelo, y fue peor: Apps Script NO ejecuta cinco cosas a la
  /// vez para la misma cuenta, las encola — así que esperaban igual, pero
  /// todas contando su propio tiempo hasta agotarlo.
  ///
  /// El error de fondo era otro: una pantalla que al abrirse dispara cinco
  /// trabajos de minutos está mal pensada, por rápido que sea cada uno.
  /// Carga y Calificaciones recorren miles de renglones; eso se pide cuando
  /// se necesita, no «por si acaso».
  ///
  /// Ahora: los tres ligeros se cuentan solos, en fila. Los dos pesados
  /// muestran un botón «Contar» y no molestan a nadie hasta que se pulsa.
  /// El botón de Excel siempre funciona, con o sin conteo.
  Future<void> _cargarEstados() async {
    for (final f in _formatos) {
      if (!_formatoActivo(f)) continue;

      // Los dos pesados esperan a que se lo pidan.
      if (f.requiereEquiv) {
        setState(() => _estado[f.clave] = {
              'cargando': false,
              'aPeticion': true,
              'sinCiclo': _cicloSel == null,
            });
        continue;
      }
      await _contarUno(f);
    }
  }

  /// Pide un archivo y espera a que el servidor lo tenga, preguntando cada
  /// cinco segundos. Ninguna consulta individual tarda: la que pide responde
  /// al instante y las de estado también. Por eso no hace falta ningún plazo
  /// largo, y el trabajo del servidor no depende de que la pantalla siga
  /// abierta — si se cierra, el archivo se genera igual y queda en Drive.
  Future<Map<String, dynamic>> _pedirYRecoger(
      String accionExcel, String filtro) async {
    // De 'siga_calif_excel' se toma 'calif'; el paquete se pide como tal.
    final que = accionExcel.contains('paquete')
        ? 'paquete'
        : accionExcel.replaceAll('siga_', '').replaceAll('_excel', '');

    final pedido = await http.get(Uri.parse(
        '$guardianUrl?${await _actorQ()}accion=siga_excel_pedir&que=$que$filtro'
        '&t=${DateTime.now().millisecondsSinceEpoch}')).timeout(const Duration(seconds: 60));   // (23-sep) sin esto, la pantalla podía quedarse esperando para siempre
    final p = jsonDecode(pedido.body) as Map<String, dynamic>;
    if (p['ok'] != true || (p['id'] ?? '').toString().isEmpty) {
      return p;   // el servidor dijo que no; se muestra su razón
    }
    final id = '${p['id']}';

    // Se pregunta hasta 120 veces cada 5 segundos: diez minutos de margen.
    // No es una espera: son consultas cortas, y entre una y otra la pantalla
    // sigue respondiendo.
    for (var i = 0; i < 120; i++) {
      await Future<void>.delayed(const Duration(seconds: 5));
      if (!mounted) return {'ok': false, 'error': 'Pantalla cerrada.'};
      try {
        final r = await http.get(Uri.parse(
            '$guardianUrl?${await _actorQ()}accion=siga_excel_estado&id=$id'
            '&t=${DateTime.now().millisecondsSinceEpoch}')).timeout(const Duration(seconds: 30));
        final d = jsonDecode(r.body) as Map<String, dynamic>;
        if (d['enProceso'] == true) continue;
        final res = d['resultado'];
        if (res is Map) return Map<String, dynamic>.from(res);
        return d;
      } catch (_) {
        // Una consulta perdida no cancela nada: se vuelve a preguntar.
        continue;
      }
    }
    return {
      'ok': false,
      'error': 'El archivo sigue generándose. No se perdió: busca el más '
          'reciente en tu Google Drive dentro de unos minutos.'
    };
  }

  /// Pide al servidor que calcule este corte y lo guarde. Tarda, pero corre
  /// del lado de Apps Script sin el corte de 120 s del proxy, así que
  /// termina. Después el conteo queda disponible al instante para siempre.
  Future<void> _precalcular(_FormatoSiga f) async {
    setState(() => _estado[f.clave] = {'cargando': true});
    try {
      // Sin plazo: este cálculo corre del lado de Google, donde hay seis
      // minutos y ningún proxy que corte. Cortarlo aquí no lo detendría, solo
      // haría que la pantalla creyera que falló algo que sí terminó.
      await http.get(Uri.parse(
          '$guardianUrl?${await _actorQ()}accion=siga_precalcular$_filtroCiclo'
          '&t=${DateTime.now().millisecondsSinceEpoch}')).timeout(const Duration(minutes: 6));   // (23-sep) lo más que dura una ejecución de Apps Script
    } catch (_) {
      // Aunque se agote la espera de este lado, el cálculo del servidor
      // sigue y guarda el resultado. Por eso se vuelve a consultar igual.
    }
    await _contarUno(f);
  }

  /// Cuenta UN formato. Se usa al abrir (los ligeros) y al pulsar «Contar».
  Future<void> _contarUno(_FormatoSiga f) async {
    if (f.requiereEquiv && _cicloSel == null) {
      setState(() => _estado[f.clave] = {'cargando': false, 'sinCiclo': true});
      return;
    }
    final filtro = f.requiereEquiv ? _filtroCiclo : '';
    setState(() => _estado[f.clave] = {'cargando': true});
    try {
          final resp = await http
              .get(Uri.parse('$guardianUrl?${await _actorQ()}accion=${f.accionDatos}$filtro'
                  '&t=${DateTime.now().millisecondsSinceEpoch}'))
              .timeout(const Duration(seconds: 45));
          final data = jsonDecode(resp.body) as Map<String, dynamic>;
          if (!mounted) return;
          setState(() {
            _estado[f.clave] = {
              'cargando': false,
              'total': data['total'] ?? 0,
              'conError': data['conError'] ?? 0,
              'sinEquiv': data['generacionesSinEquivalencia'] ?? 0,
              'gruposDerivados': data['gruposDerivados'] ?? 0,
              'ok': data['ok'] == true,
              'error': data['ok'] != true,
              // No es un error: es que este corte todavía no se ha calculado.
              'sinPrecalculo': data['sinPrecalculo'] == true,
              'calculadoEl': '${data['calculadoEl'] ?? ''}',
              'detalle': '${data['error'] ?? ''}',
            };
          });
        } catch (e) {
          if (mounted) {
            setState(() => _estado[f.clave] = {
                  'cargando': false,
                  'error': true,
                  'detalle': '$e',
                });
          }
        }
  }

  Future<void> _cargarEquivalencias() async {
    setState(() => _cargandoEquiv = true);
    try {
      final resp = await http
          .get(Uri.parse('$guardianUrl?${await _actorQ()}accion=siga_equivalencias_listar'))
          .timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _lista = ((data['equivalencias'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _cargandoEquiv = false;
      });
      // Carga/Calificaciones dependen de las equivalencias: recarga sus estados.
      _cargarEstados();
      _cargarCiclos();
    } catch (_) {
      if (mounted) setState(() => _cargandoEquiv = false);
    }
  }

  List<Map<String, dynamic>> get _visibles {
    final q = _busqueda.toLowerCase();
    return _lista.where((e) {
      if (_soloPendientes && e['capturado'] == true) return false;
      if (q.isEmpty) return true;
      return (e['programa'] ?? '').toString().toLowerCase().contains(q) ||
          (e['generacion'] ?? '').toString().toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _exportarPaquete() async {
    final periodoTxt = _cicloSel == null
        ? 'todo el histórico'
        : _cicloSel!.replaceAll('|', ' · carga ');
    // Confirmación antes de generar (son 5 archivos).
    final seguir = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Exportar paquete completo'),
        content: Text(
            'Se generarán los 5 exportables SIGA de $periodoTxt en una carpeta '
            'de Drive. Puede tardar un momento.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: cessumRed),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Generar')),
        ],
      ),
    );
    if (seguir != true) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(color: cessumRed),
            SizedBox(width: 18),
            Expanded(child: Text('Generando los 5 exportables…')),
          ],
        ),
      ),
    );
    try {
      final data = await _pedirYRecoger('paquete', _filtroCiclo);
      if (!mounted) return;
      Navigator.pop(context);
      if (data['ok'] == true &&
          (data['carpetaUrl'] ?? '').toString().isNotEmpty) {
        final generados = data['generados'] ?? 0;
        final totalReg = data['totalRegistros'] ?? 0;
        final totalErr = data['totalErrores'] ?? 0;
        final archivos = (data['archivos'] as List?) ?? [];
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Paquete generado ($generados/5)'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$totalReg registros en total.'),
                if (totalErr != 0)
                  Text('$totalErr con datos por corregir.',
                      style: const TextStyle(
                          fontSize: 12.5, color: Color(0xFFB08D57))),
                const SizedBox(height: 10),
                ...archivos.map((a) {
                  final m = Map<String, dynamic>.from(a as Map);
                  final ok = m['ok'] == true;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Row(
                      children: [
                        Icon(ok ? Icons.check_circle : Icons.error_outline,
                            size: 14,
                            color: ok
                                ? const Color(0xFF1E8E3E)
                                : Colors.red),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            ok
                                ? '${m['formato']}: ${m['total']} reg.'
                                : '${m['formato']}: ${m['error'] ?? 'error'}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cerrar')),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E8E3E),
                    foregroundColor: Colors.white),
                onPressed: () {
                  launchUrl(Uri.parse((data['carpetaUrl']).toString()),
                      mode: LaunchMode.externalApplication);
                  Navigator.pop(ctx);
                },
                icon: const Icon(Icons.folder_open),
                label: const Text('Abrir carpeta'),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text(data['error']?.toString() ?? 'No se pudo generar.'),
        ));
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text('Error: $e'),
        ));
      }
    }
  }

  Future<void> _descargarErrores() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(color: cessumRed),
            SizedBox(width: 18),
            Expanded(child: Text('Reuniendo los registros con error…')),
          ],
        ),
      ),
    );
    try {
      final resp = await http
          .get(Uri.parse(
              '$guardianUrl?${await _actorQ()}accion=siga_errores_excel$_filtroCiclo'))
          .timeout(const Duration(minutes: 2));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      Navigator.pop(context);
      final total = data['total'] ?? 0;
      if (data['ok'] == true && total == 0) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Sin errores'),
            content: const Text(
                'Ningún registro tiene errores. Todo está listo para exportar.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cerrar')),
            ],
          ),
        );
      } else if (data['ok'] == true &&
          (data['xlsxUrl'] ?? '').toString().isNotEmpty) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Reporte de errores'),
            content: Text(
                '$total registros por corregir. El Excel indica qué corregir '
                'en cada uno.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cerrar')),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor: cessumGold, foregroundColor: Colors.white),
                onPressed: () {
                  launchUrl(Uri.parse((data['xlsxUrl']).toString()),
                      mode: LaunchMode.externalApplication);
                  Navigator.pop(ctx);
                },
                icon: const Icon(Icons.download),
                label: const Text('Descargar'),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text(data['error']?.toString() ?? 'No se pudo generar.'),
        ));
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text('Error: $e'),
        ));
      }
    }
  }

  Future<void> _descargarExcel(String accion, String titulo,
      [String filtro = '']) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(color: cessumRed),
            const SizedBox(width: 18),
            Expanded(child: Text('Generando el Excel de $titulo…')),
          ],
        ),
      ),
    );
    try {
      // (ago-19) SE PIDE Y SE RECOGE, no se espera.
      // Generar el Excel de Calificaciones son minutos: recorrer 4,831 filas
      // y escribir una hoja nueva. Esperar eso desde el navegador no puede
      // funcionar, porque guardian.php corta a los 120 segundos — la barra se
      // quedaba girando para siempre. Ahora se pide (responde al instante) y
      // se pregunta cada cinco segundos si ya está.
      final data = await _pedirYRecoger(accion, filtro);
      if (!mounted) return;
      Navigator.pop(context);
      if (data['ok'] == true && (data['xlsxUrl'] ?? '').toString().isNotEmpty) {
        final total = data['total'] ?? 0;
        final err = data['conError'] ?? 0;
        final dup = data['duplicadosEliminados'] ?? 0;
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Excel de $titulo listo'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$total registros exportados.'),
                if (dup != 0)
                  Text('$dup duplicados eliminados.',
                      style: const TextStyle(fontSize: 12.5)),
                if (err != 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('$err con datos por corregir (revisa el Excel).',
                        style: const TextStyle(
                            fontSize: 12.5, color: Color(0xFFB08D57))),
                  ),
                const SizedBox(height: 6),
                Text('Incluye hoja Datos (formato SIGA) y hoja Ayuda.',
                    style: TextStyle(fontSize: 12, color: cessumMuted(context))),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cerrar')),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E8E3E),
                    foregroundColor: Colors.white),
                onPressed: () {
                  launchUrl(Uri.parse((data['xlsxUrl']).toString()),
                      mode: LaunchMode.externalApplication);
                  Navigator.pop(ctx);
                },
                icon: const Icon(Icons.download),
                label: const Text('Descargar Excel'),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text(data['error']?.toString() ?? 'No se pudo generar.'),
        ));
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text('Error: $e'),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pend = _lista.where((e) => e['capturado'] != true).length;
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Equivalencias SIGA'),
        actions: [
          IconButton(
            tooltip: 'Bitácora de exportaciones',
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SigaBitacoraScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Diagnóstico de datos',
            icon: const Icon(Icons.fact_check_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const SigaDiagnosticoScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _cargarEquivalencias();
              _cargarPeriodoFaltante();
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // (23-sep) Un solo camino para generar archivos: la Cabina SIGA.
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: cessumGold.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cessumGold.withValues(alpha: 0.4)),
            ),
            child: Row(children: [
              const Icon(Icons.info_outline, color: cessumGold),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Aquí se indica a qué ciclo escolar y carga pertenece cada generación, y el periodo de las materias que no lo tienen. '
                  'Los archivos para el portal se generan en la Cabina SIGA, después del Diagnóstico.',
                  style: TextStyle(fontSize: 12.5, color: cessumMuted(context)),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          if (_periodoFaltante.isNotEmpty) ...[
            _tarjetaPeriodoFaltante(),
            const SizedBox(height: 16),
          ],
          // ===== Sección: equivalencias =====
          const Text('Equivalencias (ciclo por generación)',
              style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w800, color: cessumRed)),
          const SizedBox(height: 4),
          Text(
            'Indica a qué ciclo escolar y carga pertenece cada generación. '
            'Habilita el filtro por ciclo y los formatos de Carga y Calificaciones. '
            'Pendientes: $pend de ${_lista.length}.',
            style: TextStyle(fontSize: 12.5, color: cessumMuted(context)),
          ),
          const SizedBox(height: 12),
          TextField(
            onChanged: (v) => setState(() => _busqueda = v),
            decoration: InputDecoration(
              hintText: 'Buscar por programa o generación…',
              prefixIcon: const Icon(Icons.search, color: cessumRed),
              isDense: true,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              FilterChip(
                label: Text('Solo pendientes ($pend)'),
                selected: _soloPendientes,
                selectedColor: cessumGold.withValues(alpha: 0.2),
                onSelected: (v) => setState(() => _soloPendientes = v),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_cargandoEquiv)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator(color: cessumRed)),
            )
          else if (_visibles.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Sin generaciones que coincidan.',
                  style: TextStyle(color: cessumMuted(context))),
            )
          else
            ..._visibles.map(_tarjetaEquiv),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ---- Guía de cierre: checklist de qué falta para exportar sin errores ----
  Widget _guiaCierre() {
    // Reúne los pasos pendientes de las distintas fuentes ya cargadas.
    final pasos = <Map<String, dynamic>>[];

    // 1) Equivalencias pendientes.
    final equivPend = _lista.where((e) => e['capturado'] != true).length;
    if (equivPend > 0) {
      pasos.add({
        'texto': '$equivPend generación(es) sin ciclo escolar asignado',
        'accion': 'Captúralas en la sección Equivalencias, abajo.',
        'listo': false,
      });
    }

    // 2) Materias sin periodo.
    if (_periodoFaltante.isNotEmpty) {
      pasos.add({
        'texto': '${_periodoFaltante.length} materia(s) sin periodo del plan',
        'accion': 'Captúralas en la tarjeta ámbar de arriba.',
        'listo': false,
      });
    }

    // 3) Errores por formato (CURP docentes, sin grupo, etc.).
    int totalErrores = 0;
    for (final f in _formatos) {
      final st = _estado[f.clave] ?? {};
      totalErrores += ((st['conError'] ?? 0) as int);
    }
    if (totalErrores > 0) {
      pasos.add({
        'texto': '$totalErrores registro(s) con datos por corregir',
        'accion': 'Descarga el reporte de errores para ver cuáles.',
        'listo': false,
      });
    }

    // 4) ¿Hay al menos un ciclo capturado? (habilita carga/calif)
    if (_ciclos.isEmpty) {
      pasos.add({
        'texto': 'Aún no hay ningún ciclo para reportar',
        'accion': 'Captura al menos una equivalencia con su ciclo y carga.',
        'listo': false,
      });
    }

    final todoListo = pasos.isEmpty;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: todoListo
            ? const Color(0xFF1E8E3E).withValues(alpha: 0.08)
            : Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: todoListo
                ? const Color(0xFF1E8E3E).withValues(alpha: 0.4)
                : cessumMuted(context).withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(todoListo ? Icons.verified : Icons.checklist,
                  color:
                      todoListo ? const Color(0xFF1E8E3E) : cessumRed,
                  size: 20),
              const SizedBox(width: 8),
              Text(
                todoListo
                    ? 'Todo listo para exportar'
                    : 'Para exportar sin errores',
                style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color:
                        todoListo ? const Color(0xFF1E8E3E) : cessumRed),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (todoListo)
            Text(
              'No hay pendientes. Elige el periodo y genera el paquete completo.',
              style: TextStyle(fontSize: 12, color: cessumMuted(context)),
            )
          else
            ...pasos.map((p) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 1),
                        child: Icon(Icons.radio_button_unchecked,
                            size: 15, color: Color(0xFFB08D57)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${p['texto']}',
                                style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600)),
                            Text('${p['accion']}',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: cessumMuted(context))),
                          ],
                        ),
                      ),
                    ],
                  ),
                )),
        ],
      ),
    );
  }

  // ---- Tarjeta: materias sin periodo (captura manual) ----
  Widget _tarjetaPeriodoFaltante() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cessumGold.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cessumGold.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.event_busy, color: cessumGold, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                    '${_periodoFaltante.length} materia(s) sin periodo del plan',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Estas materias no están en las cartas descriptivas, así que su '
            'periodo (semestre del plan) va como 99. Captúralo para precisar '
            'Oferta educativa.',
            style: TextStyle(fontSize: 11.5, color: cessumMuted(context)),
          ),
          const SizedBox(height: 8),
          ..._periodoFaltante.map((m) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: InkWell(
                  onTap: () => _editarPeriodo(m),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${m['materia']}',
                                  style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600)),
                              Text('${m['programa']} · ${m['clave']}',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: cessumMuted(context))),
                            ],
                          ),
                        ),
                        const Icon(Icons.edit, size: 16, color: cessumGold),
                      ],
                    ),
                  ),
                ),
              )),
        ],
      ),
    );
  }

  Future<void> _editarPeriodo(Map<String, dynamic> m) async {
    String periodo = '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('${m['materia']}', style: const TextStyle(fontSize: 15)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${m['programa']} · ${m['clave']}',
                  style: TextStyle(fontSize: 12, color: cessumMuted(context))),
              const SizedBox(height: 12),
              const Text('¿En qué periodo/semestre del plan se cursa?',
                  style: TextStyle(fontSize: 12.5)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(9, (i) {
                  final n = '${i + 1}';
                  return ChoiceChip(
                    label: Text(n),
                    selected: periodo == n,
                    selectedColor: cessumGold.withValues(alpha: 0.2),
                    onSelected: (_) => setLocal(() => periodo = n),
                  );
                }),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed:
                  periodo.isEmpty ? null : () => Navigator.pop(ctx, true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || periodo.isEmpty) return;
    try {
      final actor = await SessionStore.realEmail() ?? '';
      final resp = await http
          .get(Uri.parse('$guardianUrl?${await _actorQ()}accion=siga_periodo_guardar'
              '&programa=${Uri.encodeComponent((m['programa'] ?? '').toString())}'
              '&clave=${Uri.encodeComponent((m['clave'] ?? '').toString())}'
              '&materia=${Uri.encodeComponent((m['materia'] ?? '').toString())}'
              '&periodo=${Uri.encodeComponent(periodo)}'
              '&actor=${Uri.encodeComponent(actor)}'))
          .timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: Color(0xFF1E8E3E),
          content: Text('Periodo guardado.'),
        ));
        _cargarPeriodoFaltante();
        _cargarEstados();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text(data['error']?.toString() ?? 'No se pudo guardar.'),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text('Error: $e'),
        ));
      }
    }
  }

  // ---- Selector de ciclo para Carga horaria y Calificaciones ----
  Widget _selectorCiclo() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cessumRed.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.filter_alt_outlined, color: cessumRed, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Periodo a reportar',
                    style:
                        TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Elige el ciclo y carga para Carga horaria y Calificaciones. '
            'Solo se exportará ese periodo, no todo el histórico.',
            style: TextStyle(fontSize: 11.5, color: cessumMuted(context)),
          ),
          const SizedBox(height: 10),
          if (_ciclos.isEmpty)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cessumGold.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Aún no hay ciclos. Captura las equivalencias (abajo) para poder '
                'elegir un periodo.',
                style: TextStyle(fontSize: 11.5, color: cessumMuted(context)),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Todos'),
                  selected: _cicloSel == null,
                  selectedColor: cessumRed.withValues(alpha: 0.16),
                  onSelected: (_) {
                    setState(() => _cicloSel = null);
                    _cargarEstados();
                  },
                ),
                ..._ciclos.map((c) {
                  final ciclo = (c['ciclo'] ?? '').toString();
                  final carga = (c['carga'] ?? '').toString();
                  final gen = c['generaciones'] ?? 0;
                  final val = '$ciclo|$carga';
                  return ChoiceChip(
                    label: Text('$ciclo · carga $carga  ($gen gen.)'),
                    selected: _cicloSel == val,
                    selectedColor: cessumRed.withValues(alpha: 0.16),
                    onSelected: (_) {
                      setState(() => _cicloSel = val);
                      _cargarEstados();
                    },
                  );
                }),
              ],
            ),
          if (_cicloSel != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.check_circle,
                    color: Color(0xFF1E8E3E), size: 15),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    'Carga y Calificaciones se exportarán solo del periodo '
                    '${_cicloSel!.replaceAll('|', ' · carga ')}.',
                    style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF1E8E3E),
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ---- Banda de resumen: cuántos formatos listos + mini-semáforo + guía ----
  Widget _bandaResumen() {
    int listos = 0, pendientes = 0, bloqueados = 0;
    for (final f in _formatos) {
      switch (_estadoSemaforo(f)) {
        case 'listo':
          listos++;
          break;
        case 'pendiente':
          pendientes++;
          break;
        case 'bloqueado':
          bloqueados++;
          break;
      }
    }
    final total = _formatos.length;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cessumRed, cessumRed.withValues(alpha: 0.82)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.cloud_upload_outlined,
                  color: Colors.white, size: 22),
              const SizedBox(width: 8),
              Text('$listos de $total formatos listos',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _pildoraResumen(
                  const Color(0xFF6BE29A), '$listos listos'),
              const SizedBox(width: 6),
              if (pendientes > 0)
                _pildoraResumen(
                    const Color(0xFFF0D089), '$pendientes con pendientes'),
              const SizedBox(width: 6),
              if (bloqueados > 0)
                _pildoraResumen(
                    Colors.white.withValues(alpha: 0.35), '$bloqueados bloqueados'),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'Cómo usar: 1) Captura las equivalencias (ciclo por generación) '
              'abajo y la CURP de docentes en Profesores. 2) Cada formato en '
              'verde ya se puede descargar y subir al SIGA. 3) Los de ámbar '
              'traen datos por corregir; revísalos en el Excel antes de subir.',
              style: TextStyle(
                  color: Colors.white, fontSize: 11.5, height: 1.5),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: cessumRed,
                padding: const EdgeInsets.symmetric(vertical: 12),
                textStyle: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w800),
              ),
              onPressed: _exportarPaquete,
              icon: const Icon(Icons.folder_zip_outlined, size: 20),
              label: const Text('Exportar los 5 (paquete completo)'),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.6)),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const SigaDiagnosticoScreen()),
              ),
              icon: const Icon(Icons.fact_check_outlined, size: 18),
              label: const Text('Ver diagnóstico de datos'),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.6)),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              onPressed: _descargarErrores,
              icon: const Icon(Icons.rule_folder_outlined, size: 18),
              label: const Text('Descargar reporte de errores'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pildoraResumen(Color color, String texto) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(texto,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // ---- Tarjeta de un formato exportable ----
  Widget _tarjetaFormato(_FormatoSiga f) {
    final activo = _formatoActivo(f);
    final st = _estado[f.clave] ?? {};
    final cargando = st['cargando'] == true;
    final total = st['total'];
    final conError = st['conError'] ?? 0;
    final tieneError = st['error'] == true;

    Widget estadoLinea() {
      if (!activo) {
        return Text(f.nota ?? 'Pendiente de datos',
            style: const TextStyle(fontSize: 11.5, color: Color(0xFFB08D57)));
      }
      if (cargando) {
        return Row(
          children: [
            const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 8),
            Text('Contando registros…',
                style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
          ],
        );
      }
      if (st['sinCiclo'] == true) {
        return const Text('Elige un ciclo arriba para contar este formato.',
            style: TextStyle(fontSize: 11.5, color: Color(0xFFB08D57)));
      }
      if (st['sinPrecalculo'] == true) {
        return Row(children: [
          const Flexible(
            child: Text('Sin conteo todavía. El Excel funciona igual.',
                style: TextStyle(fontSize: 11.5, color: Color(0xFFB08D57))),
          ),
          const SizedBox(width: 8),
          TextButton(
            style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                visualDensity: VisualDensity.compact,
                foregroundColor: cessumRed),
            onPressed: () => _precalcular(f),
            child: const Text('Calcularlo',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        ]);
      }
      if (st['aPeticion'] == true) {
        // No se cuenta solo: son miles de renglones y casi siempre lo que se
        // quiere es el Excel, no el número.
        return Row(children: [
          Flexible(
            child: Text(f.descripcion,
                style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
          ),
          const SizedBox(width: 8),
          TextButton(
            style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                visualDensity: VisualDensity.compact,
                foregroundColor: cessumRed),
            onPressed: () => _contarUno(f),
            child: const Text('Contar',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        ]);
      }
      if (tieneError) {
        final d = '${st['detalle'] ?? ''}';
        return Text(
            d.contains('TimeoutException')
                ? 'Tardó demasiado. Acota con el tipo de periodo (arriba) y '
                    'vuelve a pulsar Contar. El botón de Excel funciona igual.'
                : d.isEmpty
                    ? 'No se pudo consultar. Toca refrescar.'
                    : 'No se pudo consultar: ${d.length > 90 ? '${d.substring(0, 90)}…' : d}',
            style: const TextStyle(fontSize: 11.5, color: Colors.red));
      }
      if (st['calculadoEl'] != null && '${st['calculadoEl']}'.isNotEmpty &&
          total != null) {
        return Text(
            '$total filas · $conError con error  ·  calculado el ${st['calculadoEl']}',
            style: TextStyle(fontSize: 11.5, color: cessumMuted(context)));
      }
      if (total == null) {
        return Text(f.descripcion,
            style: TextStyle(fontSize: 11.5, color: cessumMuted(context)));
      }
      final sinEquiv = st['sinEquiv'] ?? 0;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('$total registros',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1E8E3E))),
              if (conError != 0) ...[
                const SizedBox(width: 8),
                Text('· $conError por corregir',
                    style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFB08D57))),
              ],
            ],
          ),
          if (sinEquiv != 0)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('$sinEquiv generación(es) sin equivalencia (no incluidas)',
                  style: const TextStyle(fontSize: 10.5, color: Color(0xFFB08D57))),
            ),
          if ((st['gruposDerivados'] ?? 0) != 0)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                  '${st['gruposDerivados']} grupo(s) recuperados del padrón',
                  style: const TextStyle(
                      fontSize: 10.5, color: Color(0xFF1E8E3E))),
            ),
        ],
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: activo ? cessumMuted(context).withValues(alpha: 0.18) : Colors.black.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: (activo ? cessumRed : Colors.grey)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(f.icono,
                    color: activo ? cessumRed : Colors.grey, size: 24),
              ),
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: _colorSemaforo(_estadoSemaforo(f)),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Theme.of(context).cardColor, width: 2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(f.titulo,
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: activo
                                  ? (cessumIsDark(context)
                                      ? Colors.white
                                      : cessumInk(context))
                                  : Colors.grey)),
                    ),
                    const SizedBox(width: 8),
                    _chipEstado(_estadoSemaforo(f)),
                  ],
                ),
                const SizedBox(height: 3),
                estadoLinea(),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (activo)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E8E3E),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              onPressed: () => _descargarExcel(
                  f.accionExcel, f.titulo, f.requiereEquiv ? _filtroCiclo : ''),
              icon: const Icon(Icons.download, size: 16),
              label: const Text('Excel', style: TextStyle(fontSize: 12.5)),
            )
          else
            const Icon(Icons.lock_outline, color: Colors.grey, size: 20),
        ],
      ),
    );
  }

  // Chip con el estado en palabras claras.
  Widget _chipEstado(String estado) {
    String txt;
    switch (estado) {
      case 'listo':
        txt = 'Listo';
        break;
      case 'pendiente':
        txt = 'Con pendientes';
        break;
      case 'bloqueado':
        txt = 'Bloqueado';
        break;
      case 'vacio':
        txt = 'Sin datos aún';
        break;
      case 'error_consulta':
        txt = 'Error';
        break;
      case 'cargando':
      default:
        return const SizedBox.shrink();
    }
    final color = _colorSemaforo(estado);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(txt,
          style: TextStyle(
              fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
    );
  }

  // ---- Tarjeta de una equivalencia ----
  Widget _tarjetaEquiv(Map<String, dynamic> e) {
    final capturado = e['capturado'] == true;
    final ciclo = (e['cicloEscolar'] ?? '').toString();
    final carga = (e['noCarga'] ?? '').toString();
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          capturado ? Icons.check_circle : Icons.radio_button_unchecked,
          color: capturado ? const Color(0xFF1E8E3E) : cessumFaint(context),
        ),
        title: Text('${e['generacion']} · ${e['programa']}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        subtitle: Text(
          capturado ? 'Ciclo $ciclo · carga $carga' : 'Sin capturar',
          style: TextStyle(
            fontSize: 12.5,
            color: capturado ? const Color(0xFF1E8E3E) : cessumFaint(context),
            fontWeight: capturado ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        trailing: const Icon(Icons.edit, size: 18, color: cessumRed),
        onTap: () => _editar(e),
      ),
    );
  }

  Future<void> _editar(Map<String, dynamic> e) async {
    final ciclo =
        TextEditingController(text: (e['cicloEscolar'] ?? '').toString());
    String carga = (e['noCarga'] ?? '').toString();
    String tipoP = (e['tipoPeriodo'] ?? '4').toString();
    if (tipoP.isEmpty) tipoP = '4';

    List<String> cargasDe(String tp) {
      switch (tp) {
        case '2':
          return ['1', '2', '3', '4'];
        case '3':
          return ['1', '2', '3'];
        case '4':
        default:
          return ['1', '2'];
      }
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final cargas = cargasDe(tipoP);
          if (!cargas.contains(carga)) carga = '';
          return AlertDialog(
            title: Text('${e['generacion']} · ${e['programa']}',
                style: const TextStyle(fontSize: 15)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: ciclo,
                  decoration: const InputDecoration(
                    labelText: 'Ciclo escolar (AAAA-AAAA)',
                    hintText: 'ej. 2026-2027',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: tipoP,
                  decoration: const InputDecoration(
                    labelText: 'Tipo de periodo',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: '4', child: Text('Semestral')),
                    DropdownMenuItem(value: '3', child: Text('Cuatrimestral')),
                    DropdownMenuItem(value: '2', child: Text('Trimestral')),
                  ],
                  onChanged: (v) => setLocal(() {
                    tipoP = v ?? '4';
                    carga = '';
                  }),
                ),
                const SizedBox(height: 14),
                Text('Carga en el ciclo (no_carga)',
                    style: TextStyle(fontSize: 12, color: cessumMuted(context))),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  children: cargas
                      .map((c) => ChoiceChip(
                            label: Text('Carga $c'),
                            selected: carga == c,
                            selectedColor: cessumRed.withValues(alpha: 0.16),
                            onSelected: (_) => setLocal(() => carga = c),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 4),
                Text(
                  tipoP == '2'
                      ? 'Trimestral: 4 cargas por ciclo'
                      : tipoP == '3'
                          ? 'Cuatrimestral: 3 cargas por ciclo'
                          : 'Semestral: 2 cargas por ciclo',
                  style: TextStyle(fontSize: 11, color: cessumFaint(context)),
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancelar')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: cessumRed, foregroundColor: Colors.white),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Guardar'),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true) return;
    final cicloTxt = ciclo.text.trim();
    if (cicloTxt.isNotEmpty && !RegExp(r'^\d{4}-\d{4}$').hasMatch(cicloTxt)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: Colors.orange,
          content: Text('El ciclo debe ser AAAA-AAAA (ej. 2026-2027).'),
        ));
      }
      return;
    }
    try {
      final actor = await SessionStore.realEmail() ?? '';
      final resp = await http
          .get(Uri.parse('$guardianUrl?${await _actorQ()}accion=siga_equivalencia_guardar'
              '&programa=${Uri.encodeComponent((e['programa'] ?? '').toString())}'
              '&generacion=${Uri.encodeComponent((e['generacion'] ?? '').toString())}'
              '&cicloEscolar=${Uri.encodeComponent(cicloTxt)}'
              '&noCarga=${Uri.encodeComponent(carga)}'
              '&tipoPeriodo=${Uri.encodeComponent(tipoP)}'
              '&actor=${Uri.encodeComponent(actor)}'))
          .timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: Color(0xFF1E8E3E),
          content: Text('Equivalencia guardada.'),
        ));
        _cargarEquivalencias();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text(data['error']?.toString() ?? 'No se pudo guardar.'),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text('Error: $e'),
        ));
      }
    }
  }
}

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'cessum_ui.dart';
import 'constants.dart';
import 'helpers.dart';

// Pantallas donde se resuelve cada pendiente (mismas que el panel de administración).
import 'adaptaciones_admin_screen.dart';
import 'agenda_profesores_screen.dart';
import 'altas_anomalias_screen.dart';
import 'analisis_calificaciones_screen.dart';
import 'aspirantes_pendientes_screen.dart';
import 'avance_captura_screen.dart';
import 'baja_docente_screen.dart';
import 'bajas_lista_screen.dart';
import 'bajas_pago_screen.dart';
import 'bandeja_correos_screen.dart';
import 'becas_admin_screen.dart';
import 'boletas_periodo_screen.dart';
import 'buzon_eventos_admin_screen.dart';
import 'calidad_datos_screen.dart';
import 'cambio_programa_screen.dart';
import 'centro_pagos_screen.dart';
import 'contratos_faltantes_screen.dart';
import 'contratos_validacion_screen.dart';
import 'convenios_admin_screen.dart';
import 'credenciales_admin_screen.dart';
import 'dictaminacion_screen.dart';
import 'estudios_admin_screen.dart';
import 'horarios_admin_screen.dart';
import 'incidencias_admin_screen.dart';
import 'justificaciones_lista_screen.dart';
import 'materias_sin_maestro_screen.dart';
import 'no_adeudo_admin_screen.dart';
import 'pagos_docentes_screen.dart';
import 'pagos_screen.dart';
import 'planeaciones_revision_screen.dart';
import 'quejas_admin_screen.dart';
import 'recomienda_admin_screen.dart';
import 'recursamientos_panel_screen.dart';
import 'reingresos_admin_screen.dart';
import 'riesgo_screen.dart';
import 'seguimiento_docente_screen.dart';
import 'siga_screen.dart';
import 'solicitudes_correccion_screen.dart';
import 'tesis_solicitudes_admin_screen.dart';
import 'titulacion_admin_screen.dart';
import 'titulacion_cierre_screen.dart';
import 'tramites_lista_screen.dart';
import 'validacion_actas_screen.dart';
import 'vencimientos_screen.dart';

/// (9-oct-2026) PANEL DE TODOS LOS PENDIENTES.
///
/// Una sola lista con TODO lo que espera una decisión o una respuesta:
///   · el registro único de trámites (25 hojas: trámites, incidencias,
///     correcciones, justificaciones, credenciales, constancias, bajas,
///     cambios, reingresos, recursamientos, becas, quejas, buzón, convenios,
///     tesis, contratos, horarios, referidos, planeaciones…),
///   · los dictámenes de CESSUMEX y COINEDU,
///   · 35 fuentes por ruta (actas, pagos, captura, grupos sin maestro,
///     invitaciones, revisiones, boletas, titulación, aspirantes,
///     vencimientos, posibles bajas —por pago y reportadas por docentes—,
///     SIGA, riesgo, adaptaciones…),
///   · y los correos que piden algo y nadie ha contestado.
/// Cada renglón tiene «Abrir en la app» (la pantalla donde se resuelve) y,
/// cuando existe, «Enlace» (la fila de la hoja, el panel de la revista o el
/// hilo en Gmail). Se carga por partes para que empiece a verse pronto.
///
/// GET pendientes_panel&parte=registro|rutas|correos[&fresco=1][&dias=14]
class PendientesPanelScreen extends StatefulWidget {
  const PendientesPanelScreen({super.key});

  @override
  State<PendientesPanelScreen> createState() => _PendientesPanelScreenState();
}

class _PendientesPanelScreenState extends State<PendientesPanelScreen> {
  static const List<String> _partes = ['registro', 'rutas', 'correos'];
  static const Map<String, String> _nombreParte = {
    'registro': 'trámites y dictámenes',
    'rutas': 'pendientes por área',
    'correos': 'correos sin responder',
  };

  final Map<String, String> _estadoParte = {}; // cargando · ok · error
  final Map<String, String> _errorParte = {};
  // (9-oct-2026) «rutas» llega por tramos (el proxy corta a los 120 s): cuántas fuentes van de cuántas.
  int _rutasLeidas = 0;
  int _rutasTotal = 0;
  final List<Map<String, dynamic>> _secciones = [];
  final List<String> _errores = [];
  final List<String> _noLeidas = [];
  final Set<String> _cerradas = {};
  Map<String, dynamic> _resumen = {};
  String _nivel = 'todos'; // todos · vencido · critico · alerta · ok · espera
  String _area = '';
  String _q = '';
  int _dias = 14;
  String _actor = '';
  bool _fresco = false;
  final TextEditingController _buscar = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cargarTodo();
  }

  @override
  void dispose() {
    _buscar.dispose();
    super.dispose();
  }

  Future<void> _cargarTodo({bool fresco = false}) async {
    _actor = await SessionStore.validEmail() ?? '';
    setState(() {
      _fresco = fresco;
      _secciones.clear();
      _errores.clear();
      _noLeidas.clear();
      _resumen = {};
      for (final p in _partes) {
        _estadoParte[p] = 'cargando';
        _errorParte[p] = '';
      }
    });
    for (final p in _partes) {
      await _cargarParte(p, fresco: fresco);
    }
  }

  Future<void> _cargarParte(String parte, {bool fresco = false, int desde = 0}) async {
    if (mounted) {
      setState(() {
        _estadoParte[parte] = 'cargando';
        _errorParte[parte] = '';
        if (desde == 0) {
          _secciones.removeWhere((s) => s['_parte'] == parte);
          if (parte == 'rutas') {
            _rutasLeidas = 0;
            _rutasTotal = 0;
          }
        }
      });
    }
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'pendientes_panel',
        'parte': parte,
        'dias': '$_dias',
        if (parte == 'rutas') 'desde': '$desde',
        if (parte == 'rutas') 'tope': '85000',
        if (fresco) 'fresco': '1',
        if (_actor.isNotEmpty) 'actor': _actor,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 150));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) {
        throw Exception('${data['error'] ?? 'Sin respuesta del Guardián.'}');
      }
      final secs = ((data['secciones'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map)..['_parte'] = parte)
          .toList();
      if (!mounted) return;
      final sig = data['siguiente'];
      final hayMas = parte == 'rutas' && sig is num && sig.toInt() >= 0;
      setState(() {
        for (final sec in secs) {
          // Misma fuente en dos tramos (no debería pasar): se junta, no se duplica.
          final previa = _secciones.cast<Map<String, dynamic>?>().firstWhere(
              (x) => x!['_parte'] == parte && '${x['clave']}' == '${sec['clave']}',
              orElse: () => null);
          if (previa == null) {
            _secciones.add(sec);
          } else {
            (previa['items'] as List).addAll((sec['items'] as List?) ?? []);
            previa['total'] = ((previa['total'] as num?)?.toInt() ?? 0) + ((sec['total'] as num?)?.toInt() ?? 0);
            previa['vencidos'] = ((previa['vencidos'] as num?)?.toInt() ?? 0) + ((sec['vencidos'] as num?)?.toInt() ?? 0);
          }
        }
        for (final e in ((data['errores'] as List?) ?? [])) {
          final t = '$e';
          if (!_errores.contains(t)) _errores.add(t);
        }
        if (parte == 'rutas') {
          _rutasTotal = (data['fuentesTotal'] as num?)?.toInt() ?? _rutasTotal;
          _rutasLeidas = hayMas ? sig.toInt() : _rutasTotal;
          // Lo «no leído» de un tramo es lo que sigue en el próximo: solo cuenta al final.
          if (!hayMas) {
            for (final e in ((data['fuentesNoLeidas'] as List?) ?? [])) {
              final t = '$e';
              if (!_noLeidas.contains(t)) _noLeidas.add(t);
            }
          }
        } else {
          for (final e in ((data['fuentesNoLeidas'] as List?) ?? [])) {
            final t = '$e';
            if (!_noLeidas.contains(t)) _noLeidas.add(t);
          }
        }
        _estadoParte[parte] = hayMas ? 'cargando' : 'ok';
        _recalcularResumen();
      });
      if (hayMas) {
        await _cargarParte(parte, fresco: fresco, desde: sig.toInt());
      }
    } on TimeoutException {
      if (mounted) {
        setState(() {
          _estadoParte[parte] = 'error';
          _errorParte[parte] = 'Tardó más de 2 minutos y medio. Vuelve a intentarlo.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _estadoParte[parte] = 'error';
          _errorParte[parte] = '$e'.replaceFirst('Exception: ', '');
        });
      }
    }
  }

  void _recalcularResumen() {
    var total = 0, vencidos = 0, criticos = 0, alerta = 0, enTiempo = 0, sinPlazo = 0, espera = 0;
    for (final s in _secciones) {
      for (final it in _itemsDe(s)) {
        total++;
        if (it['espera'] == true) {
          espera++;
          continue;
        }
        switch ('${it['nivel'] ?? ''}') {
          case 'vencido':
            vencidos++;
            break;
          case 'critico':
            criticos++;
            break;
          case 'alerta':
            alerta++;
            break;
          case 'ok':
            enTiempo++;
            break;
          default:
            sinPlazo++;
        }
      }
    }
    _resumen = {
      'total': total,
      'vencidos': vencidos,
      'criticos': criticos,
      'alerta': alerta,
      'enTiempo': enTiempo,
      'sinPlazo': sinPlazo,
      'enEspera': espera,
    };
  }

  List<Map<String, dynamic>> _itemsDe(Map<String, dynamic> s) =>
      ((s['items'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

  List<String> get _areas {
    final a = <String>{};
    for (final s in _secciones) {
      final x = '${s['area'] ?? ''}'.trim();
      if (x.isNotEmpty) a.add(x);
    }
    final l = a.toList()..sort();
    return l;
  }

  bool _pasa(Map<String, dynamic> it) {
    if (_nivel == 'espera') {
      if (it['espera'] != true) return false;
    } else if (_nivel != 'todos') {
      if (it['espera'] == true) return false;
      final n = '${it['nivel'] ?? ''}';
      if (_nivel == 'ok' && (n == 'ok' || n == 'sinPlazo' || n.isEmpty)) {
        // en tiempo y sin plazo se ven juntos
      } else if (n != _nivel) {
        return false;
      }
    }
    final q = _q.trim().toLowerCase();
    if (q.isEmpty) return true;
    final texto = [
      it['quien'], it['matricula'], it['asunto'], it['estado'], it['id'],
      it['fuente'], it['accion'], it['area']
    ].map((x) => '${x ?? ''}'.toLowerCase()).join(' ');
    return texto.contains(q);
  }

  Color _colorNivel(String nivel, bool espera) {
    if (espera) return Colors.blueGrey;
    switch (nivel) {
      case 'vencido':
        return cessumRed;
      case 'critico':
        return cessumGold;
      case 'alerta':
        return Colors.orange.shade700;
      case 'ok':
        return Colors.green.shade700;
      default:
        return Colors.blueGrey;
    }
  }

  String _textoNivel(Map<String, dynamic> it) {
    if (it['espera'] == true) return 'Espera al solicitante';
    final n = '${it['nivel'] ?? ''}';
    final hv = (it['horasVencido'] as num?)?.toInt() ?? 0;
    final hr = (it['horasRestantes'] as num?)?.toInt() ?? 0;
    switch (n) {
      case 'vencido':
        return hv > 0 ? 'Vencido · ${_horas(hv)} de más' : 'Vencido';
      case 'critico':
        return hr > 0 ? 'Crítico · quedan ${_horas(hr)}' : 'Crítico';
      case 'alerta':
        return hr > 0 ? 'Quedan ${_horas(hr)}' : 'Por vencer';
      case 'ok':
        return hr > 0 ? 'En tiempo · ${_horas(hr)}' : 'En tiempo';
      default:
        final d = (it['dias'] as num?)?.toInt();
        return d == null ? 'Sin plazo' : (d == 0 ? 'Hoy' : 'Hace $d día${d == 1 ? '' : 's'}');
    }
  }

  String _horas(int h) => h >= 48 ? '${(h / 24).round()} días' : '$h h';

  /// La pantalla de la app donde se resuelve ese pendiente. null = no hay
  /// pantalla propia (queda el enlace).
  Widget? _pantallaDe(Map<String, dynamic> it) {
    final pantalla = '${it['pantalla'] ?? ''}'.trim();
    final hoja = '${it['hoja'] ?? ''}'.trim();
    final clave = pantalla.isNotEmpty ? pantalla : _pantallaPorHoja(hoja);
    switch (clave) {
      case 'actas':
        return const ValidacionActasScreen();
      case 'pagosDocentes':
        return const PagosDocentesScreen();
      case 'pagosAclarar':
        return const CentroPagosScreen();
      case 'pagos':
        return const PagosScreen();
      case 'captura':
        return const AvanceCapturaScreen();
      case 'sinMaestro':
        return const MateriasSinMaestroScreen();
      case 'agenda':
        return const AgendaProfesoresScreen();
      case 'horario':
        return const HorariosAdminScreen();
      case 'revisiones':
        return const SeguimientoDocenteScreen();
      case 'boletas':
        return const BoletasPeriodoScreen();
      case 'tesis':
        return const TesisSolicitudesAdminScreen();
      case 'titulacion':
        return const TitulacionAdminScreen();
      case 'art62':
        return const TitulacionCierreScreen();
      case 'contratos':
        return const ContratosFaltantesScreen();
      case 'contratosPendientes':
        return const ContratosValidacionScreen();
      case 'aspirantes':
      case 'prospectos':
        return const AspirantesPendientesScreen();
      case 'altas':
        return const AltasAnomaliasScreen();
      case 'vencimientos':
        return const VencimientosScreen();
      case 'posibleBaja':
      case 'riesgo':
        return const RiesgoScreen();
      case 'bajaDocente':
        return const BajaDocenteScreen();
      case 'bajasPago':
        return const BajasPagoScreen();
      case 'siga':
        return SigaScreen(actor: _actor);
      case 'promedios':
        return const AnalisisCalificacionesScreen();
      case 'adaptaciones':
        return const AdaptacionesAdminScreen();
      case 'usicamm':
      case 'becas':
        return const BecasAdminScreen();
      case 'sugerencias':
      case 'buzon':
      case 'mensajes':
        return const BuzonEventosAdminScreen();
      case 'hallazgos':
        return const CalidadDatosScreen();
      case 'devoluciones':
        return const CentroPagosScreen();
      case 'tramites':
      case 'credenciales':
        return const TramitesListaScreen();
      case 'credencialesDocentes':
        return const CredencialesAdminScreen();
      case 'mesa':
      case 'incidencias':
        return const IncidenciasAdminScreen();
      case 'correcciones':
        return const SolicitudesCorreccionScreen();
      case 'justificaciones':
        return const JustificacionesListaScreen(modoAdmin: true);
      case 'constancias':
        return const EstudiosAdminScreen();
      case 'noadeudo':
      case 'noAdeudo':
        return const NoAdeudoAdminScreen();
      case 'bajas':
        return const BajasListaScreen();
      case 'programa':
      case 'cambioPrograma':
        return const CambioProgramaScreen();
      case 'reingresos':
        return ReingresosAdminScreen(actor: _actor);
      case 'recursamientos':
        return const RecursamientosPanelScreen();
      case 'quejas':
        return const QuejasAdminScreen();
      case 'convenios':
        return const ConveniosAdminScreen();
      case 'referidos':
        return const RecomiendaAdminScreen();
      case 'planeaciones':
        return const PlaneacionesRevisionScreen();
      case 'dictaminacion':
        return const DictaminacionScreen();
      case 'bandejaCorreo':
        return const BandejaCorreosScreen();
      default:
        return null;
    }
  }

  String _pantallaPorHoja(String hoja) {
    const m = {
      'Tramites': 'tramites',
      'Incidencias': 'mesa',
      'Solicitudes de corrección': 'correcciones',
      'Justificaciones': 'justificaciones',
      'Credenciales': 'tramites',
      'CredencialesDocentes': 'credencialesDocentes',
      'Constancia estudios': 'constancias',
      'No adeudo': 'noadeudo',
      'Bajas': 'bajas',
      'CambioPrograma': 'programa',
      'Reingresos': 'reingresos',
      'Recursamientos': 'recursamientos',
      'RecursamientoAutogestivo': 'recursamientos',
      'BecasSolicitudesFormales': 'becas',
      'Becas solicitudes': 'becas',
      'Quejas': 'quejas',
      'Buzón': 'buzon',
      'ConveniosSolicitudes': 'convenios',
      'TesisSolicitudes': 'tesis',
      'ContratosPendientes': 'contratosPendientes',
      'CambiosHorario': 'horario',
      'InasistenciasDocentes': 'horario',
      'Recomienda referidos': 'referidos',
      'PlaneacionesEntrega': 'planeaciones',
    };
    return m[hoja] ?? '';
  }

  void _abrir(Map<String, dynamic> it) {
    final w = _pantallaDe(it);
    if (w == null) {
      final enlace = '${it['enlace'] ?? ''}';
      if (enlace.isNotEmpty) {
        Helpers.abrirUrlExterna(enlace, context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Este pendiente no tiene pantalla propia en la app ni enlace.')));
      }
      return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => w));
  }

  Widget _chip(String texto, Color color, {IconData? icono}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icono != null) ...[Icon(icono, size: 12, color: color), const SizedBox(width: 3)],
          Text(texto, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
        ]),
      );

  Widget _filaItem(Map<String, dynamic> it) {
    final espera = it['espera'] == true;
    final color = _colorNivel('${it['nivel'] ?? ''}', espera);
    final tienePantalla = _pantallaDe(it) != null;
    final enlace = '${it['enlace'] ?? ''}';
    final quien = '${it['quien'] ?? ''}'.trim();
    final mat = '${it['matricula'] ?? ''}'.trim();
    final asunto = '${it['asunto'] ?? ''}'.trim();
    final estado = '${it['estado'] ?? ''}'.trim();
    final id = '${it['id'] ?? ''}'.trim();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: color, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  quien.isNotEmpty ? quien : (asunto.isNotEmpty ? asunto : (id.isNotEmpty ? id : 'Pendiente')),
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: cessumInk(context)),
                ),
              ),
              const SizedBox(width: 6),
              _chip(_textoNivel(it), color, icono: espera ? Icons.hourglass_empty : Icons.schedule),
            ],
          ),
          if (quien.isNotEmpty && asunto.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(asunto, style: TextStyle(fontSize: 12.5, color: cessumInk(context), height: 1.35)),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              [
                if (mat.isNotEmpty) mat,
                if (id.isNotEmpty && id != mat) id,
                if (estado.isNotEmpty) estado,
                if ('${it['fecha'] ?? ''}'.isNotEmpty) '${it['fecha']}',
                if ('${it['limite'] ?? ''}'.isNotEmpty) 'límite ${it['limite']}',
              ].join(' · '),
              style: TextStyle(fontSize: 11.5, color: cessumMuted(context)),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text('→ ${it['accion'] ?? 'Atender'}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cessumRed)),
              ),
              if (tienePantalla)
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: cessumRed, visualDensity: VisualDensity.compact),
                  onPressed: () => _abrir(it),
                  icon: const Icon(Icons.open_in_new, size: 15),
                  label: const Text('Abrir en la app', style: TextStyle(fontSize: 12)),
                ),
              if (enlace.isNotEmpty)
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: cessumGold, visualDensity: VisualDensity.compact),
                  onPressed: () => Helpers.abrirUrlExterna(enlace, context),
                  icon: const Icon(Icons.link, size: 15),
                  label: Text(_etiquetaEnlace(enlace), style: const TextStyle(fontSize: 12)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _etiquetaEnlace(String url) {
    if (url.contains('docs.google.com/spreadsheets')) return 'Fila en la hoja';
    if (url.contains('mail.google.com')) return 'Abrir en Gmail';
    if (url.contains('cessumex')) return 'Panel CESSUMEX';
    if (url.contains('coinedu')) return 'Panel COINEDU';
    return 'Enlace';
  }

  Widget _seccion(Map<String, dynamic> s) {
    final items = _itemsDe(s).where(_pasa).toList();
    if (items.isEmpty) return const SizedBox.shrink();
    final clave = '${s['clave'] ?? s['titulo']}';
    final cerrada = _cerradas.contains(clave);
    final vencidos = items.where((x) => x['espera'] != true && '${x['nivel']}' == 'vencido').length;
    final pantallaSec = _pantallaDe({'pantalla': s['pantalla'] ?? '', 'hoja': items.first['hoja'] ?? ''});
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: (vencidos > 0 ? cessumRed : cessumGold).withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() {
              if (cerrada) {
                _cerradas.remove(clave);
              } else {
                _cerradas.add(clave);
              }
            }),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              child: Row(
                children: [
                  Icon(cerrada ? Icons.chevron_right : Icons.expand_more, color: cessumRed),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${s['titulo'] ?? ''}',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: cessumInk(context))),
                        Text('${s['area'] ?? ''}${'${s['accion'] ?? ''}'.isNotEmpty ? ' · ${s['accion']}' : ''}',
                            style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
                      ],
                    ),
                  ),
                  if (vencidos > 0) ...[
                    _chip('$vencidos vencido${vencidos == 1 ? '' : 's'}', cessumRed),
                    const SizedBox(width: 6),
                  ],
                  _chip('${items.length}', cessumGold),
                  if (pantallaSec != null)
                    IconButton(
                      tooltip: 'Abrir la pantalla donde se resuelven',
                      icon: const Icon(Icons.open_in_new, size: 18, color: cessumRed),
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => pantallaSec)),
                    ),
                ],
              ),
            ),
          ),
          if (!cerrada)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: Column(children: items.map(_filaItem).toList()),
            ),
        ],
      ),
    );
  }

  Widget _resumenWidget() {
    Widget n(String v, String etq, Color c, String nivel) => Expanded(
          child: InkWell(
            onTap: () => setState(() => _nivel = _nivel == nivel ? 'todos' : nivel),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: _nivel == nivel ? c.withValues(alpha: 0.12) : null,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(children: [
                Text(v, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: c)),
                Text(etq, style: TextStyle(fontSize: 10.5, color: cessumMuted(context)), textAlign: TextAlign.center),
              ]),
            ),
          ),
        );
    final r = _resumen;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        n('${r['total'] ?? 0}', 'Todos', cessumInk(context), 'todos'),
        n('${r['vencidos'] ?? 0}', 'Vencidos', cessumRed, 'vencido'),
        n('${r['criticos'] ?? 0}', 'Críticos', cessumGold, 'critico'),
        n('${r['alerta'] ?? 0}', 'Por vencer', Colors.orange.shade700, 'alerta'),
        n('${(r['enTiempo'] ?? 0) + (r['sinPlazo'] ?? 0)}', 'En tiempo', Colors.green.shade700, 'ok'),
        n('${r['enEspera'] ?? 0}', 'Esperan al solicitante', Colors.blueGrey, 'espera'),
      ]),
    );
  }

  Widget _estadoPartes() {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: _partes.map((p) {
        final e = _estadoParte[p] ?? '';
        final color = e == 'ok' ? Colors.green.shade700 : (e == 'error' ? cessumRed : cessumGold);
        final avance = (p == 'rutas' && _rutasTotal > 0) ? ' $_rutasLeidas/$_rutasTotal' : '';
        return InkWell(
          onTap: e == 'cargando' ? null : () => _cargarParte(p, fresco: _fresco),
          child: _chip(
            e == 'cargando'
                ? 'Cargando ${_nombreParte[p]}$avance…'
                : (e == 'error' ? 'Error en ${_nombreParte[p]}$avance · reintentar' : '${_nombreParte[p]}$avance ✓'),
            color,
            icono: e == 'cargando' ? Icons.hourglass_top : (e == 'error' ? Icons.refresh : Icons.check),
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final secciones = List<Map<String, dynamic>>.from(_secciones)
      ..retainWhere((s) => _area.isEmpty || '${s['area'] ?? ''}' == _area);
    secciones.sort((a, b) {
      final va = (a['vencidos'] as num?)?.toInt() ?? 0, vb = (b['vencidos'] as num?)?.toInt() ?? 0;
      if (va != vb) return vb - va;
      return ((b['total'] as num?)?.toInt() ?? 0) - ((a['total'] as num?)?.toInt() ?? 0);
    });
    final cargando = _partes.any((p) => _estadoParte[p] == 'cargando');
    final erroresPartes = _partes.where((p) => _estadoParte[p] == 'error').map((p) => '${_nombreParte[p]}: ${_errorParte[p]}').toList();
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Panel de pendientes · todo lo que espera', style: TextStyle(fontSize: 16)),
        actions: [
          PopupMenuButton<int>(
            tooltip: 'Días de correo revisados',
            icon: const Icon(Icons.mail_outline),
            onSelected: (d) {
              setState(() => _dias = d);
              _cargarParte('correos', fresco: true);
            },
            itemBuilder: (_) => [7, 14, 30].map((d) => PopupMenuItem(value: d, child: Text('Correos de los últimos $d días${d == _dias ? ' ✓' : ''}'))).toList(),
          ),
          IconButton(
            tooltip: 'Volver a leer todo (sin caché)',
            icon: const Icon(Icons.refresh),
            onPressed: cargando ? null : () => _cargarTodo(fresco: true),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 32),
        children: [
          _estadoPartes(),
          const SizedBox(height: 10),
          _resumenWidget(),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _buscar,
                  onChanged: (v) => setState(() => _q = v),
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.search, size: 18),
                    hintText: 'Buscar por nombre, matrícula, asunto, folio o estado',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    suffixIcon: _q.isEmpty
                        ? null
                        : IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () { _buscar.clear(); setState(() => _q = ''); }),
                  ),
                ),
              ),
              if (_areas.length > 1) ...[
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _area.isEmpty ? '' : _area,
                  underline: const SizedBox.shrink(),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('Todas las áreas', style: TextStyle(fontSize: 12.5))),
                    ..._areas.map((a) => DropdownMenuItem(value: a, child: Text(a, style: const TextStyle(fontSize: 12.5)))),
                  ],
                  onChanged: (v) => setState(() => _area = v ?? ''),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          if (erroresPartes.isNotEmpty || _errores.isNotEmpty || _noLeidas.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cessumGold.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: cessumGold.withValues(alpha: 0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Lo que no se pudo leer', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: cessumGold)),
                  for (final e in erroresPartes) Text('• $e', style: const TextStyle(fontSize: 12)),
                  for (final e in _errores) Text('• $e', style: const TextStyle(fontSize: 12)),
                  if (_noLeidas.isNotEmpty) Text('• Sin tiempo para: ${_noLeidas.join(', ')} (toca «reintentar» o actualiza).', style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          if (secciones.isEmpty && !cargando)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Column(children: [
                Icon(Icons.inbox_outlined, size: 40, color: cessumMuted(context)),
                const SizedBox(height: 8),
                Text('No hay pendientes con estos filtros.', style: TextStyle(color: cessumMuted(context))),
              ]),
            ),
          ...secciones.map(_seccion),
          if (cargando)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator(color: cessumRed)),
            ),
        ],
      ),
    );
  }
}

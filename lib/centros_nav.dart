// centros_nav.dart · CESSUM · (24-sep-2026)
//
// MAPA DE NAVEGACIÓN DE LOS CENTROS INTELIGENTES.
// El Centro de mando, la Bandeja única y el Expediente 360 no repiten lo que
// ya existe: cada tarjeta o solicitud abre LA PANTALLA que ya la atiende.
// Este archivo es el único lugar donde se decide qué clave abre qué pantalla.
import 'package:flutter/material.dart';

import 'auth/session_store.dart';
import 'agenda_profesores_screen.dart';
import 'alerta_riesgo_screen.dart';
import 'altas_anomalias_screen.dart';
import 'avance_captura_screen.dart';
import 'bajas_pago_screen.dart';
import 'bitacora_screen.dart';
import 'calendario_admin_screen.dart';
import 'contratos_validacion_screen.dart';
import 'curps_pendientes_screen.dart';
import 'directorio_docentes_screen.dart';
import 'huerfanos_screen.dart';
import 'registro_accesos_screen.dart';
import 'salud_datos_screen.dart';
import 'seguimiento_docente_screen.dart';
import 'seguimiento_pagos_admin_screen.dart';
import 'siga_screen.dart';
import 'bajas_lista_screen.dart';
import 'bandeja_solicitudes_screen.dart';
import 'becas_admin_screen.dart';
import 'cambio_programa_solicitudes_screen.dart';
import 'cambios_horario_lista_screen.dart';
import 'estudios_admin_screen.dart';
import 'hallazgos_screen.dart';
import 'incidencias_admin_screen.dart';
import 'justificaciones_lista_screen.dart';
import 'materias_sin_maestro_screen.dart';
import 'no_adeudo_admin_screen.dart';
import 'pagos_profesores_screen.dart';
import 'pagos_por_aclarar_screen.dart';
import 'recordatorio_invitaciones_screen.dart';
import 'recursamientos_panel_screen.dart';
import 'retencion_screen.dart';
import 'reingresos_admin_screen.dart';
import 'riesgo_screen.dart';
import 'solicitudes_correccion_screen.dart';
import 'tesis_solicitudes_admin_screen.dart';
import 'titulacion_admin_screen.dart';
import 'tramites_lista_screen.dart';
import 'validacion_actas_screen.dart';

/// Abre la pantalla que atiende [clave]. Devuelve false si la clave no tiene
/// pantalla (entonces la tarjeta se muestra sin acción).
Future<bool> abrirPantallaCentro(BuildContext context, String clave) async {
  Widget? destino;
  switch (clave) {
    case 'actas':
      destino = const ValidacionActasScreen();
      break;
    case 'pagosAclarar':
      destino = const PagosPorAclararScreen();
      break;
    case 'riesgo':
      destino = const RiesgoScreen();
      break;
    case 'captura':
      destino = const AvanceCapturaScreen();
      break;
    case 'sinMaestro':
      destino = const MateriasSinMaestroScreen();
      break;
    case 'bandeja':
      destino = const BandejaSolicitudesScreen();
      break;
    case 'mesa':
      destino = const IncidenciasAdminScreen();
      break;
    case 'hallazgos':
      destino = const HallazgosScreen();
      break;
    case 'justificaciones':
      destino = const JustificacionesListaScreen(modoAdmin: true);
      break;
    case 'correcciones':
      destino = const SolicitudesCorreccionScreen();
      break;
    case 'horario':
      destino = const CambiosHorarioListaScreen();
      break;
    case 'programa':
      destino = const CambioProgramaSolicitudesScreen();
      break;
    case 'bajas':
      destino = const BajasListaScreen();
      break;
    case 'constancias':
      destino = const EstudiosAdminScreen();
      break;
    case 'noadeudo':
      destino = const NoAdeudoAdminScreen();
      break;
    case 'reingresos':
      final actor = await SessionStore.realEmail() ?? '';
      destino = ReingresosAdminScreen(actor: actor);
      break;
    case 'recursamientos':
      destino = const RecursamientosPanelScreen();
      break;
    case 'titulacion':
      destino = const TitulacionAdminScreen();
      break;
    case 'tramites':
      destino = const TramitesListaScreen();
      break;
    case 'tesis':
      destino = const TesisSolicitudesAdminScreen();
      break;
    case 'becas':
      destino = const BecasAdminScreen();
      break;
    // Fase 3: calidad de datos y auditoría.
    case 'saludDatos':
      destino = const SaludDatosScreen();
      break;
    case 'huerfanos':
      destino = const HuerfanosScreen();
      break;
    case 'curps':
      destino = const CurpsPendientesScreen();
      break;
    case 'anomalias':
      destino = const AltasAnomaliasScreen();
      break;
    case 'siga':
      final actorSiga = await SessionStore.realEmail() ?? '';
      destino = SigaScreen(actor: actorSiga);
      break;
    case 'bitacora':
      destino = const BitacoraScreen();
      break;
    case 'accesos':
      destino = const RegistroAccesosScreen();
      break;
    // Fase 4: retención, cobranza, planeación, calendario y docente.
    case 'riesgoAlerta':
      destino = const AlertaRiesgoScreen();
      break;
    case 'retencion':
      destino = const RetencionScreen();
      break;
    case 'agenda':
      destino = const AgendaProfesoresScreen();
      break;
    case 'invitaciones':
      destino = const RecordatorioInvitacionesScreen();
      break;
    case 'calendarioAdmin':
      destino = const CalendarioAdminScreen();
      break;
    case 'pagosSeguimiento':
      destino = const SeguimientoPagosAdminScreen();
      break;
    case 'bajasPago':
      destino = const BajasPagoScreen();
      break;
    case 'directorio':
      destino = const DirectorioDocentesScreen();
      break;
    case 'seguimientoDocente':
      destino = const SeguimientoDocenteScreen();
      break;
    case 'contratos':
      destino = const ContratosValidacionScreen();
      break;
    case 'pagosProfesores':
      destino = const PagosProfesoresScreen();
      break;
  }
  if (destino == null || !context.mounted) return false;
  final d = destino;
  await Navigator.push(context, MaterialPageRoute(builder: (_) => d));
  return true;
}

/// Ícono representativo de cada clave, para tarjetas y listas.
IconData iconoCentro(String clave) {
  switch (clave) {
    case 'actas':
      return Icons.fact_check_outlined;
    case 'pagosAclarar':
    case 'pago':
      return Icons.payments_outlined;
    case 'riesgo':
      return Icons.warning_amber_rounded;
    case 'captura':
    case 'calificacion':
      return Icons.grading_outlined;
    case 'sinMaestro':
      return Icons.person_off_outlined;
    case 'bandeja':
    case 'tramite':
    case 'tramites':
      return Icons.inbox_outlined;
    case 'mesa':
      return Icons.support_agent_outlined;
    case 'hallazgos':
      return Icons.lightbulb_outline;
    case 'justificaciones':
    case 'justificacion':
      return Icons.event_busy_outlined;
    case 'correcciones':
      return Icons.edit_note_outlined;
    case 'horario':
      return Icons.schedule_outlined;
    case 'programa':
      return Icons.swap_horiz_outlined;
    case 'bajas':
    case 'baja':
      return Icons.logout_outlined;
    case 'constancias':
    case 'noadeudo':
      return Icons.description_outlined;
    case 'reingresos':
      return Icons.login_outlined;
    case 'recursamientos':
      return Icons.replay_outlined;
    case 'titulacion':
      return Icons.school_outlined;
    case 'tesis':
      return Icons.menu_book_outlined;
    case 'becas':
      return Icons.volunteer_activism_outlined;
    case 'saludDatos':
    case 'descuadres':
    case 'nombres':
      return Icons.health_and_safety_outlined;
    case 'huerfanos':
      return Icons.link_off;
    case 'duplicados':
      return Icons.copy_all_outlined;
    case 'curps':
    case 'sinCurp':
      return Icons.badge_outlined;
    case 'anomalias':
      return Icons.report_gmailerrorred_outlined;
    case 'siga':
    case 'sigaClaves':
      return Icons.account_balance_outlined;
    case 'bitacora':
      return Icons.history_toggle_off;
    case 'accesos':
      return Icons.login_outlined;
  }
  return Icons.circle_outlined;
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'auth/session_store.dart';
import 'salud_datos_screen.dart';
import 'validacion_actas_screen.dart';
import 'continuidades_screen.dart';
import 'expediente_persona_screen.dart';
import 'padron_overrides_screen.dart';
import 'semaforo_riesgo_screen.dart';
import 'asistente_ia_screen.dart';
import 'becas_admin_screen.dart';
import 'pulso_admin_screen.dart';
import 'coinedu_admin_screen.dart';

/// Tablero de pendientes (admin): un vistazo a lo que requiere atención, con
/// acceso directo a cada herramienta.
class TableroPendientesScreen extends StatefulWidget {
  const TableroPendientesScreen({super.key});

  @override
  State<TableroPendientesScreen> createState() =>
      _TableroPendientesScreenState();
}

class _TableroPendientesScreenState extends State<TableroPendientesScreen> {
  bool _cargando = true;
  String? _error;
  Map<String, dynamic> _r = {};

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
      final actor = await SessionStore.realEmail() ?? '';
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'pendientes_resumen',
        'actor': actor,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 120));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'No autorizado');
      if (!mounted) return;
      setState(() {
        _r = data;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo cargar ($e)';
      });
    }
  }

  /// Texto de apoyo con la antigüedad: "3 pagos de hoy" y "3 que llevan diez
  /// días" son el mismo número con urgencias opuestas.
  String _sub(String claveDias, String base) {
    final d = _n(_r[claveDias]);
    if (d <= 0) return base;
    return '$base · el más antiguo lleva $d día${d == 1 ? '' : 's'}';
  }

  /// Una semana sin atender es el umbral en que un pendiente deja de ser
  /// rutina. Es criterio de lectura, no una regla institucional.
  bool _urge(String claveDias) => _n(_r[claveDias]) >= 7;

  void _aviso(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(m), duration: const Duration(seconds: 4)));
  }

  int _n(dynamic v) =>
      v is int ? v : int.tryParse('${v ?? 0}') ?? 0;

  void _ir(Widget pantalla) {
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => pantalla))
        .then((_) => _cargar());
  }

  Widget _tarjeta({
    required IconData icono,
    required String titulo,
    required String sub,
    required int n,
    required Color color,
    required VoidCallback onTap,
  }) {
    final hay = n > 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(icono, color: color),
        ),
        title: Text(titulo,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
        subtitle: Text(sub, style: const TextStyle(fontSize: 12)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
              decoration: BoxDecoration(
                color: (hay ? color : const Color(0xFF1E8E3E))
                    .withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('$n',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: hay ? color : const Color(0xFF1E8E3E),
                  )),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 20),
          ],
        ),
        onTap: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Tablero de pendientes'),
        actions: [
          IconButton(
              onPressed: _cargando ? null : _cargar,
              icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(
                            style: FilledButton.styleFrom(
                                backgroundColor: cessumRed),
                            onPressed: _cargar,
                            child: const Text('Reintentar')),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _cargar,
                  color: cessumRed,
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      _tarjeta(
                        icono: Icons.fact_check,
                        titulo: 'Actas por validar',
                        sub: _n(_r['actasVencidas']) > 0
                            ? '${_n(_r['actasVencidas'])} con plazo vencido'
                            : 'Pendientes de validación',
                        n: _n(_r['actasPorValidar']),
                        color: _n(_r['actasVencidas']) > 0
                            ? cessumRed
                            : cessumGold,
                        onTap: () => _ir(const ValidacionActasScreen()),
                      ),
                      // (ago-9) LO QUE FALTABA POR NOTIFICAR. Esta barra solo
                      // contaba actas y calidad de datos; todo lo demás que
                      // espera decisión —pagos, becas, tesis, justificaciones,
                      // cambios de horario, reposiciones, grupos sin docente—
                      // solo existía en el correo diario. Si ese correo se
                      // archiva, nadie sabe qué falta.
                      // Cada tarjeta solo aparece SI TIENE PENDIENTES: una
                      // barra con doce ceros deja de leerse en una semana.
                      if (_n(_r['pagosPorValidar']) > 0)
                        _tarjeta(
                          icono: Icons.payments_outlined,
                          titulo: 'Pagos por validar',
                          sub: _sub('pagosDias', 'Comprobantes de alumnos'),
                          n: _n(_r['pagosPorValidar']),
                          color: _urge('pagosDias') ? cessumRed : cessumGold,
                          onTap: () => _aviso(
                              'Ábrelos en Admin → Seguimiento de pagos.'),
                        ),
                      if (_n(_r['becasPorDictaminar']) > 0)
                        _tarjeta(
                          icono: Icons.school_outlined,
                          titulo: 'Becas por dictaminar',
                          sub: _sub('becasDias',
                              'Resoluciones que subieron los alumnos'),
                          n: _n(_r['becasPorDictaminar']),
                          color: _urge('becasDias') ? cessumRed : cessumGold,
                          onTap: () => _ir(const BecasAdminScreen()),
                        ),
                      if (_n(_r['tesisSolicitudes']) > 0)
                        _tarjeta(
                          icono: Icons.menu_book_outlined,
                          titulo: 'Solicitudes de tutor de tesis',
                          sub: _sub('tesisDias', 'Esperan asignación de asesor'),
                          n: _n(_r['tesisSolicitudes']),
                          color: _urge('tesisDias') ? cessumRed : cessumGold,
                          onTap: () => _aviso(
                              'Ábrelas en Admin → Solicitudes de tutor.'),
                        ),
                      if (_n(_r['justificaciones']) > 0)
                        _tarjeta(
                          icono: Icons.event_busy_outlined,
                          titulo: 'Justificaciones de inasistencia',
                          sub: _sub('justificacionesDias',
                              'Esperan dictamen de Vicerrectoría'),
                          n: _n(_r['justificaciones']),
                          color: _urge('justificacionesDias')
                              ? cessumRed
                              : cessumGold,
                          onTap: () => _aviso(
                              'Ábrelas en Admin → Justificaciones.'),
                        ),
                      if (_n(_r['cambiosHorario']) > 0)
                        _tarjeta(
                          icono: Icons.schedule_outlined,
                          titulo: 'Cambios de día u hora',
                          sub: _sub('cambiosDias', 'Solicitudes de docentes'),
                          n: _n(_r['cambiosHorario']),
                          color: _urge('cambiosDias') ? cessumRed : cessumGold,
                          onTap: () => _aviso(
                              'Ábrelos en Admin → Trámites y documentos.'),
                        ),
                      if (_n(_r['reposiciones']) > 0)
                        _tarjeta(
                          icono: Icons.event_repeat_outlined,
                          titulo: 'Reposiciones de sesión',
                          sub: _sub('reposicionesDias',
                              'Sesiones que el docente va a reponer'),
                          n: _n(_r['reposiciones']),
                          color: _urge('reposicionesDias')
                              ? cessumRed
                              : cessumGold,
                          onTap: () => _aviso(
                              'Ábrelas en Admin → Trámites y documentos.'),
                        ),
                      if (_n(_r['gruposSinDocente']) > 0)
                        _tarjeta(
                          icono: Icons.person_off_outlined,
                          titulo: 'Grupos sin docente asignado',
                          sub: 'Si no se asigna, el periodo arranca sin clase',
                          n: _n(_r['gruposSinDocente']),
                          color: cessumRed,
                          onTap: () => _aviso(
                              'Ábrelos en Admin → Agenda de profesores.'),
                        ),
                      if (_n(_r['coineduPorDictaminar']) > 0)
                        _tarjeta(
                          icono: Icons.workspace_premium_outlined,
                          titulo: 'COINEDU · por dictaminar',
                          sub: _sub('coineduDias',
                              'Ponencias y carteles del congreso'),
                          n: _n(_r['coineduPorDictaminar']),
                          color: _urge('coineduDias') ? cessumRed : cessumGold,
                          onTap: () => _ir(const CoineduAdminScreen()),
                        ),
                      if (_n(_r['automatizacionesDetenidas']) > 0)
                        _tarjeta(
                          icono: Icons.sync_problem_outlined,
                          titulo: 'Automatizaciones detenidas',
                          sub: 'Mientras estén paradas, nadie recibe sus avisos',
                          n: _n(_r['automatizacionesDetenidas']),
                          color: cessumRed,
                          onTap: () => _ir(const PulsoAdminScreen()),
                        ),
                      if (_n(_r['erroresApp24h']) > 0)
                        _tarjeta(
                          icono: Icons.bug_report_outlined,
                          titulo: 'Errores de la app (24 h)',
                          sub: 'Fallas que reportó la propia aplicación',
                          n: _n(_r['erroresApp24h']),
                          color: cessumGold,
                          onTap: () => _ir(const PulsoAdminScreen()),
                        ),
                      _tarjeta(
                        icono: Icons.compare_arrows,
                        titulo: 'Calificaciones en conflicto',
                        sub: 'Misma materia con notas distintas',
                        n: _n(_r['conflictos']),
                        color: cessumRed,
                        onTap: () => _ir(const SaludDatosScreen()),
                      ),
                      _tarjeta(
                        icono: Icons.link,
                        titulo: 'Continuidades por vincular',
                        sub: 'Alumnos con varias matrículas',
                        n: _n(_r['continuidades']),
                        color: cessumGold,
                        onTap: () => _ir(const ContinuidadesScreen()),
                      ),
                      _tarjeta(
                        icono: Icons.copy_all,
                        titulo: 'Registros duplicados',
                        sub: 'Misma matrícula y materia repetidas',
                        n: _n(_r['duplicados']),
                        color: cessumRed,
                        onTap: () => _ir(const SaludDatosScreen()),
                      ),
                      _tarjeta(
                        icono: Icons.rule,
                        titulo: 'Calificaciones fuera de rango',
                        sub: 'Valores menores a 6 o mayores a 10',
                        n: _n(_r['fueraRango']),
                        color: cessumRed,
                        onTap: () => _ir(const SaludDatosScreen()),
                      ),
                      _tarjeta(
                        icono: Icons.mail_outline,
                        titulo: 'Alumnos sin correo',
                        sub: 'No pueden recibir su boleta',
                        n: _n(_r['sinCorreo']),
                        color: cessumGold,
                        onTap: () => _ir(const PadronOverridesScreen()),
                      ),
                      const SizedBox(height: 6),
                      const Padding(
                        padding: EdgeInsets.fromLTRB(4, 8, 4, 6),
                        child: Text('Herramientas',
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: cessumRed,
                                fontSize: 13)),
                      ),
                      Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: const Icon(Icons.person_search,
                              color: cessumGold),
                          title: const Text('Expediente de la persona'),
                          subtitle: const Text(
                              'Maestría y doctorado juntos (misma persona)'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () =>
                              _ir(const ExpedientePersonaScreen()),
                        ),
                      ),
                      Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading:
                              const Icon(Icons.edit_note, color: cessumGold),
                          title: const Text('Padrón — correcciones'),
                          subtitle: const Text(
                              'Arreglar modalidad, correo, agregar alumno…'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () =>
                              _ir(const PadronOverridesScreen()),
                        ),
                      ),
                      Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: const Icon(Icons.local_fire_department,
                              color: cessumGold),
                          title: const Text('Semáforo de riesgo'),
                          subtitle: const Text(
                              'Deserción: conexión, reprobadas y acompañamiento'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () =>
                              _ir(const SemaforoRiesgoScreen()),
                        ),
                      ),
                      Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: const Icon(Icons.auto_awesome,
                              color: cessumGold),
                          title: const Text('Asistente CESSUM (IA)'),
                          subtitle: const Text(
                              'Pregunta a tus datos o pide redactar documentos'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _ir(const AsistenteIaScreen()),
                        ),
                      ),
                      Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading:
                              const Icon(Icons.dataset, color: cessumGold),
                          title: const Text('Salud de datos'),
                          subtitle: const Text(
                              'Limpiezas, conflictos y deshacer'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _ir(const SaludDatosScreen()),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}

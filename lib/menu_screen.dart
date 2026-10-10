import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'about_screen.dart';
import 'admin_config.dart';
import 'admin_preview_screen.dart';
import 'queja_screen.dart';
import 'beca_convocatoria_alumno_screen.dart';
import 'auth/session_store.dart';
import 'cartas_descriptivas_screen.dart';
import 'mi_progreso_screen.dart';
import 'mi_credencial_screen.dart';
import 'mis_clases_screen.dart';
import 'mis_tramites_screen.dart';
import 'mis_documentos_screen.dart';
import 'calendario_screen.dart';
import 'buzon_screen.dart';
import 'admin_herramientas_screen.dart';
import 'matriz_grupo_screen.dart';
import 'ver_como_profesor_screen.dart';
import 'firmas_docentes_screen.dart';
import 'firma_alumno_screen.dart';
import 'salud_datos_screen.dart';
import 'tablero_pendientes_screen.dart';
import 'avance_captura_screen.dart';
import 'bitacora_screen.dart';
import 'roles_admin_screen.dart';
import 'estado_conexion.dart';
import 'respaldos_screen.dart';
import 'theme_controller.dart';
import 'accesos_uso_screen.dart';
import 'graficas_aprobacion_screen.dart';
import 'documentos_emitidos_screen.dart';
import 'acerca_screen.dart';
import 'constants.dart';
import 'cessum_ui.dart';   // (23-sep) cessumMuted, usado en la tarjeta de Finanzas
import 'helpers.dart';
import 'grabaciones_clase_screen.dart';
import 'becas_screen.dart';
import 'justificacion_faltas_screen.dart';
import 'mesa_ayuda_screen.dart';
import 'onboarding_dialog.dart';
import 'avisos_screen.dart';
import 'notificaciones_screen.dart';
import 'evaluacion_docente_screen.dart';
import 'recursamientos_screen.dart';
import 'asistente_alumno_screen.dart';
import 'ayuda_fab.dart';
import 'mi_boleta_screen.dart';
import 'dart:async';
import 'dart:ui' as ui;   // (4-oct-2026) desenfoque detrás de la carpeta abierta
import 'dart:convert' show jsonDecode, jsonEncode;
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http_eval;
import 'package:url_launcher/url_launcher.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'solicitud_factura_screen.dart';
import 'solicitud_tramites_screen.dart';
import 'solicitud_baja_screen.dart';
import 'solicitud_cambio_programa_screen.dart';
import 'profile_setup_screen.dart';
import 'student_autolink.dart';
import 'student_profile.dart';
import 'alumnos_service.dart';
import 'apa_referencias_screen.dart';
import 'calculadora_promedio_screen.dart';
import 'recordatorios_screen.dart';
import 'formatos_screen.dart';
import 'mensajes_screen.dart';
import 'reingreso_alumno_screen.dart';
import 'referidos_screen.dart';
import 'cuenta_baja_screen.dart';
import 'acceso_service.dart';
import 'identidad_screen.dart';
import 'perfil_aprendizaje_screen.dart';
import 'docente_modos_screen.dart';
import 'becas_admin_screen.dart';
import 'avance_plan_screen.dart';
import 'encuesta_screen.dart';
import 'encuesta_resultados_screen.dart';
import 'mi_titulacion_screen.dart';
import 'mi_expediente_titulacion_screen.dart';
import 'solicitar_tutor_screen.dart';
import 'tesis_convenio_screen.dart';
import 'mis_pendientes_screen.dart';
import 'mis_calificaciones_screen.dart';
import 'pagos_hub_screen.dart';
import 'juegos_hub_screen.dart';
import 'solicitud_adaptacion_modalidad_screen.dart';



import 'tutorias_alumno_screen.dart';
import 'tareas_alumno_screen.dart';
import 'recursos_alumno_screen.dart';
import 'documentos_online_screen.dart';
import 'welcome_screen.dart';
import 'active_profile.dart';
import 'estudios_screen.dart';
import 'eventos_screen.dart';
import 'buzon_screen.dart';
import 'mi_horario_screen.dart';
import 'materias_alumno_screen.dart';
import 'convenios_alumno_screen.dart';
import 'avisos_alumno_screen.dart';
import 'mi_aula_screen.dart';
import 'contacto_screen.dart';
import 'mi_panel_screen.dart';
import 'finanzas_screen.dart';
import 'salud_screen.dart';
import 'senales_screen.dart';
import 'altas_screen.dart';
import 'simulador_screen.dart';
import 'mi_ruta_screen.dart';

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  String _version = 'v1.0.0';
  StudentProfile? _perfil;
  Map<String, dynamic>? _hoy;
  Timer? _hoyTimer;
  List<Map<String, dynamic>> _avisos = [];
  int _evalPendientes = 0;
  int _notisNoLeidas = 0;
  int _pendTramites = 0;
  String _pendTitulacion = '';
  String _pendTitulacionQuien = '';
  bool _esAdmin = false;
  // (22-sep) Finanzas: solo Rectoría, Vicerrectoría y Administración y
  // Finanzas. Más estricto que _esAdmin, que incluye coordinaciones.
  bool _esFinanzas = false;
  // (ago-27) Si el alumno está dado de baja, puede reintegrarse. Se consulta
  // al abrir el menú y SOLO a él se le muestra la tarjeta: una opción de
  // «volver a estudiar» en el menú de alguien inscrito confunde y asusta.
  bool _puedeReingresar = false;

  Future<void> _cargarReingreso() async {
    final p = _perfil;
    if (p == null || p.matricula.isEmpty) return;
    try {
      final r = await http_eval
          .get(Uri.parse(
              '$guardianUrl?accion=reingreso_elegible&matricula=${Uri.encodeComponent(p.matricula)}'))
          .timeout(const Duration(seconds: 30));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] == true && d['elegible'] == true && mounted) {
        setState(() => _puedeReingresar = true);
      }
    } catch (_) {}
  }

  Future<void> _cargarEvalPendientes() async {
    final p = _perfil;
    if (p == null || p.matricula.isEmpty) return;
    try {
      final r = await http_eval
          .get(Uri.parse(
              '$guardianUrl?accion=evaluaciones_pendientes&matricula=${Uri.encodeComponent(p.matricula)}'))
          .timeout(const Duration(seconds: 30));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] == true && mounted) {
        setState(
            () => _evalPendientes = (d['pendientes'] as List).length);
      }
    } catch (_) {}
  }

  // Invitación destacada: si el alumno tiene pendiente la evaluación de su
  // materia más reciente, se muestra un banner persuasivo en el menú (NO
  // bloquea la navegación; solo invita a responder).
  Map<String, dynamic>? _evalObligatoria;
  Future<void> _verificarEvaluacionObligatoria() async {
    final p = _perfil;
    if (p == null || p.matricula.isEmpty) return;
    try {
      final r = await http_eval
          .get(Uri.parse(
              '$guardianUrl?accion=evaluacion_obligatoria&matricula=${Uri.encodeComponent(p.matricula)}'))
          .timeout(const Duration(seconds: 30));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true || !mounted) return;
      setState(() {
        _evalObligatoria = d['obligatoria'] == null
            ? null
            : Map<String, dynamic>.from(d['obligatoria'] as Map);
      });
    } catch (_) {}
  }

  // (25-sep) BUZÓN DE SUGERENCIAS. Cada sugerencia llega a Vicerrectoría y,
  // cuando se atiende, el alumno recibe la respuesta en su campanita.
  Widget _tarjetaSugerencia() {
    return Material(
      color: cessumGold.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _enviarSugerencia,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cessumGold.withValues(alpha: 0.5)),
          ),
          child: Row(children: [
            const Icon(Icons.lightbulb_outline, color: cessumGold, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('¿Tienes alguna sugerencia para la app? Ayúdanos a mejorar',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: cessumInk(context))),
                const SizedBox(height: 3),
                Text(
                  'Cualquier idea puede operarse. Todos tus comentarios serán tomados en cuenta '
                  'y en escasos días verás los cambios que nos pides.',
                  style: TextStyle(fontSize: 12, height: 1.35, color: cessumMuted(context)),
                ),
              ]),
            ),
            const Icon(Icons.chevron_right, color: cessumGold),
          ]),
        ),
      ),
    );
  }

  Future<void> _enviarSugerencia() async {
    final p = _perfil;
    final ctl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.lightbulb_outline, color: cessumGold),
          SizedBox(width: 8),
          Expanded(child: Text('Tu sugerencia para la app', style: TextStyle(fontSize: 17))),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Cuéntanos qué cambiarías, qué te gustaría que hiciera la app o qué se te complica. '
              'Te avisaremos por la campanita cuando lo atendamos.',
              style: TextStyle(fontSize: 13, height: 1.4)),
          const SizedBox(height: 10),
          TextField(
            controller: ctl,
            minLines: 3,
            maxLines: 6,
            maxLength: 2000,
            autofocus: true,
            decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Escribe aquí tu idea…'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
    final texto = ctl.text.trim();
    ctl.dispose();
    if (ok != true || texto.length < 5 || !mounted) return;
    try {
      final correo = await SessionStore.validEmail() ?? '';
      final r = await http_eval
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'sugerencia_app',
                'matricula': p?.matricula ?? '',
                'correo': correo,
                'nombre': p?.nombreCompleto ?? '',
                'texto': texto,
                'pantalla': 'Menú',
              }))
          .timeout(const Duration(seconds: 60));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: d['ok'] == true ? Colors.green : cessumRed,
        duration: const Duration(seconds: 6),
        content: Text('${d['ok'] == true ? (d['mensaje'] ?? '¡Gracias por tu sugerencia!') : (d['error'] ?? 'No se pudo enviar.')}'),
      ));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            backgroundColor: cessumRed, content: Text('No se pudo enviar. Intenta de nuevo en un momento.')));
      }
    }
  }

  // (25-sep) RED DE SEGURIDAD PARA BAJAS. Quien ya estaba adentro —con su
  // perfil guardado desde antes de la baja— seguía usando la app como si nada.
  // Al abrir el menú se consulta el padrón en vivo: si el correo está de baja,
  // se borra el perfil guardado y se regresa a la bienvenida, que le muestra
  // el aviso con «Solicitar reingreso». No aplica al administrador que usa
  // «Ver como alumno».
  Future<void> _verificarBajaEnMenu() async {
    try {
      final real = (await SessionStore.realEmail())?.trim().toLowerCase() ?? '';
      final correo = (await SessionStore.validEmail())?.trim().toLowerCase() ?? '';
      if (correo.isEmpty || (real.isNotEmpty && real != correo)) return;
      final res = await AlumnosService.buscar(correo, preferirAlumno: true);
      if (res.estado != EstadoAlumno.baja || !mounted) return;
      await StudentProfile.clear();
      await ActiveProfile.clear();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const WelcomeScreen()),
        (route) => false,
      );
    } catch (_) {}
  }

  // (25-sep) CAMPAÑA DE CELULARES. Si el alumno no ha registrado su celular,
  // se le pide UNA vez por sesión (puede decir «Más tarde»).
  static bool _celularPreguntado = false;
  Future<void> _verificarCelular() async {
    final p = _perfil;
    if (p == null || p.matricula.isEmpty || _celularPreguntado) return;
    _celularPreguntado = true;
    try {
      final r = await http_eval
          .get(Uri.parse('$guardianUrl?accion=celular_estado&matricula=${Uri.encodeComponent(p.matricula)}'))
          .timeout(const Duration(seconds: 30));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true || d['tiene'] == true || !mounted) return;
    } catch (_) {
      return;
    }
    final ctl = TextEditingController();
    var acepta = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Row(children: [
            Icon(Icons.phone_iphone, color: cessumRed),
            SizedBox(width: 8),
            Expanded(child: Text('Registra tu celular', style: TextStyle(fontSize: 17))),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text(
                'Lo usamos para avisarte a tiempo de tus materias, pagos y trámites. Escríbelo a 10 dígitos.',
                style: TextStyle(fontSize: 13.5, height: 1.4)),
            const SizedBox(height: 10),
            TextField(
              controller: ctl,
              keyboardType: TextInputType.phone,
              maxLength: 14,
              decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), labelText: 'Celular', hintText: '6421234567'),
            ),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: acepta,
              onChanged: (v) => setLocal(() => acepta = v == true),
              title: const Text('Acepto recibir avisos de CESSUM por WhatsApp', style: TextStyle(fontSize: 13)),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Más tarde')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    final texto = ctl.text.trim();
    ctl.dispose();
    if (ok != true || texto.isEmpty || !mounted) return;
    try {
      final r = await http_eval
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({'accion': 'celular_guardar', 'matricula': p.matricula, 'celular': texto, 'acepta': acepta}))
          .timeout(const Duration(seconds: 40));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: d['ok'] == true ? Colors.green : cessumRed,
        content: Text(d['ok'] == true ? 'Celular registrado. ¡Gracias!' : '${d['error'] ?? 'No se pudo guardar.'}'),
      ));
    } catch (_) {}
  }

  // Banner persuasivo para responder la evaluación docente más reciente.
  Widget _bannerEvaluacion() {
    final obl = _evalObligatoria;
    final p = _perfil;
    if (obl == null || p == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cessumGold, cessumGold.withValues(alpha: 0.85)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.volunteer_activism, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Tu opinión hace mejores tus clases',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Tienes pendiente evaluar ${obl['materia'] ?? 'tu materia más reciente'} '
            'con ${obl['docente'] ?? 'tu docente'}. Es anónima y te toma menos '
            'de 2 minutos.',
            style: const TextStyle(
                color: Colors.white, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: cessumGold,
                padding: const EdgeInsets.symmetric(vertical: 10),
                textStyle: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w800),
              ),
              onPressed: () async {
                final ok = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EvaluacionObligatoriaGate(
                      perfil: p,
                      obligatoria: obl,
                    ),
                  ),
                );
                if (ok == true && mounted) {
                  setState(() => _evalObligatoria = null);
                  _cargarEvalPendientes();
    _cargarReingreso();
                  _verificarEvaluacionObligatoria();
                }
              },
              icon: const Icon(Icons.rate_review, size: 18),
              label: const Text('Evaluar ahora'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _cargarPendientes() async {
    final p = _perfil;
    if (p == null || p.matricula.isEmpty) return;
    try {
      final r = await http_eval
          .get(Uri.parse(
              '$guardianUrl?accion=pendientes_alumno&matricula=${Uri.encodeComponent(p.matricula)}'))
          .timeout(const Duration(seconds: 30));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] == true && mounted) {
        setState(() {
          _pendTramites = (d['tramites'] ?? 0) as int;
          _pendTitulacion = (d['titulacionEtapa'] ?? '') as String;
          _pendTitulacionQuien = (d['titulacionQuien'] ?? '') as String;
        });
      }
    } catch (_) {}
  }

  Widget _tarjetaPendiente({
    required IconData icon,
    required String texto,
    required Color color,
    VoidCallback? onTap,
  }) {
    final inner = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
          if (onTap != null) Icon(Icons.chevron_right, color: color),
        ],
      ),
    );
    return Material(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(12),
      child: onTap == null
          ? inner
          : InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              child: inner,
            ),
    );
  }

  /// (22-sep) Los tableros nuevos, como tarjetas visibles del menú de
  /// administración. Finanzas solo para Rectoría, Vicerrectoría y
  /// Administración y Finanzas.
  Widget _tablerosDireccion() {
    Widget tarjeta(String titulo, String detalle, IconData icono, Widget destino) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: cessumRed.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => destino)),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cessumRed.withValues(alpha: 0.30)),
              ),
              child: Row(children: [
                Icon(icono, color: cessumRed, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(titulo,
                          style: const TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.w800)),
                      Text(detalle,
                          style: TextStyle(
                              fontSize: 11.5, color: cessumMuted(context))),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: cessumRed),
              ]),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6, top: 2),
          child: Text('Tableros de dirección',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: cessumMuted(context))),
        ),
        if (_esFinanzas)
          tarjeta('Finanzas · estados de cuenta',
              'Suba el estado de cuenta de BBVA: gastos, histórico, alertas y asistente.',
              Icons.account_balance, const FinanzasScreen()),
        tarjeta('Salud del sistema',
            'Disparadores, colas pendientes, clases y datos: qué está detenido.',
            Icons.monitor_heart_outlined, const SaludScreen()),
        tarjeta('Señales académicas',
            'Riesgo por alumno y materias que hunden la permanencia, con razones.',
            Icons.insights_outlined, const SenalesScreen()),
        tarjeta('Altas de inscripción',
            'Cada solicitud con sus pasos comprobados y qué le falta.',
            Icons.fact_check_outlined, const AltasScreen()),
        tarjeta('Simulador de grupos',
            'Ingreso, costo docente y punto de equilibrio antes de abrir un grupo.',
            Icons.calculate_outlined, const SimuladorScreen()),
      ],
    );
  }

  Future<void> _verificarAdmin() async {
    try {
      final correo = (await SessionStore.validEmail()) ?? '';
      if (mounted) {
        setState(() {
          _esAdmin = esAdmin(correo);
          _esFinanzas = kFinanzasCorreos.contains(correo.trim().toLowerCase());
        });
      }
    } catch (_) {}
  }

  Future<void> _abrirUrl(String accion) async {
    try {
      await launchUrl(Uri.parse('$guardianUrl?accion=$accion'),
          mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank');
    } catch (_) {}
  }

  Future<void> _cargarAvisos() async {
    final p = _perfil;
    if (p == null) return;
    try {
      final lista = await AvisosService.para(p);
      if (mounted) setState(() => _avisos = lista);
    } catch (_) {/* sin avisos si falla la red */}
  }

  Future<void> _cargarNotis() async {
    final p = _perfil;
    if (p == null) return;
    try {
      final correo = (await SessionStore.validEmail()) ?? '';
      final uri = Uri.parse('$guardianUrl?accion=notificaciones'
          '&correo=${Uri.encodeComponent(correo)}'
          '&matricula=${Uri.encodeComponent(p.matricula)}');
      final resp =
          await http_eval.get(uri).timeout(const Duration(seconds: 20));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (mounted && data['ok'] == true) {
        setState(() => _notisNoLeidas = (data['noLeidas'] ?? 0) as int);
      }
    } catch (_) {/* sin badge si falla la red */}
  }

  @override
  void initState() {
    super.initState();
    _cargarTodo();
    _revisarCuenta();
    // (ago-19) REGISTRAR LA ENTRADA. Esto faltaba.
    //
    // AccesoService existía y no lo llamaba nadie: la hoja Accesos se llenaba
    // solo con lo poco que entraba por otras vías. Por eso «nunca ha entrado a
    // la plataforma» aparecía en alumnos que sí entran — el dato no era falso,
    // simplemente no existía.
    //
    // El servicio ya trae su propio freno de 30 minutos, así que abrir el
    // menú diez veces al día no llena la hoja de basura.
    AccesoService.registrar();
  }

  /// (ago-19) Si la cuenta está dada de baja, se lleva al alumno a una
  /// pantalla que le explica qué pasó y cómo comunicarse.
  ///
  /// Antes, quien estaba de baja entraba al menú y encontraba todo vacío:
  /// sin materias, sin calificaciones, con botones que no respondían. La
  /// conclusión natural es «la app se descompuso», y quien quería volver
  /// dejaba de intentarlo.
  ///
  /// Solo aplica a alumnos: un docente o un administrativo nunca tiene este
  /// estado, y hacerles la consulta sería ruido.
  Future<void> _revisarCuenta() async {
    try {
      final correo = await SessionStore.validEmail();
      if (correo == null || correo.isEmpty) return;
      final baja = await CuentaBajaScreen.revisar(correo);
      if (baja == null || !mounted) return;
      // Reemplaza el menú en vez de apilarse encima: no tiene sentido dejar
      // debajo una pantalla que no va a funcionar.
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => CuentaBajaScreen(datos: baja)),
      );
    } catch (_) {
      // En silencio: si la consulta falla, más vale dejar entrar a alguien
      // de baja que dejar fuera a un alumno activo por un problema de red.
    }
  }

  Future<void> _cargarTodo() async {
    final infoFuture = PackageInfo.fromPlatform();
    // Carga el perfil y, de paso, lo re-sincroniza con el padrón (corrige
    // Programa/Modalidad/Generación al formato oficial si hiciera falta).
    final perfilFuture = StudentAutoLink.sincronizarPerfilGuardado();

    try {
      final info = await infoFuture;
      if (mounted) {
        setState(() {
          _version = 'v${info.version}';
        });
      }
    } catch (_) {}

    final perfil = await perfilFuture;
    if (mounted) {
      setState(() {
        _perfil = perfil;
      });
      _cargarAvisos();
      _cargarHoy();
      _cargarEvalPendientes();
      _cargarNotis();
      _cargarPendientes();
      _verificarAdmin();
      _pulsoCheck(perfil);
      // (25-sep) Red de seguridad: un alumno dado de baja no se queda en el menú.
      _verificarBajaEnMenu();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) mostrarOnboardingSiAplica(context, perfil);
        if (mounted) _verificarEvaluacionObligatoria();
        // (25-sep) Campaña de celulares: se pide una vez por sesión, después
        // de que el menú y la bienvenida ya se mostraron.
        Future.delayed(const Duration(seconds: 5), () {
          if (mounted) _verificarCelular();
        });
      });
    }
  }

  // Cambiar perfil: NO borra los perfiles guardados, solo va a la pantalla
  // de bienvenida para que el usuario elija (Estudiante / Profesor / Soy nuevo).
  // Esto permite que estudiantes que tambien son profesores conserven ambos perfiles.
  Future<void> _cambiarPerfil(BuildContext context) async {
    // Si quien usa la app es administrador, "Cambiar perfil" lo regresa al
    // PANEL DE ADMINISTRADOR (para elegir a otro alumno). Para un usuario
    // normal, va a la pantalla de bienvenida como siempre.
    final correo = await SessionStore.validEmail();
    if (!mounted) return;
    final destino =
        esAdmin(correo) ? const AdminPreviewScreen() : const WelcomeScreen();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => destino),
    );
  }

  void _abrirAcercaDe() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AboutScreen()),
    ).then((_) {
      _refrescarPerfil();
    });
  }

  Future<void> _refrescarPerfil() async {
    final perfil = await StudentProfile.load();
    if (mounted) {
      setState(() {
        _perfil = perfil;
      });
      _cargarAvisos();
      _cargarHoy();
      _cargarEvalPendientes();
      _cargarPendientes();
      _verificarAdmin();
    }
  }

  /// Abre "Mi perfil" (el editor de datos del alumno). Si aún no hay perfil
  /// guardado, lo manda a la pantalla de bienvenida para identificarse.
  Future<void> _abrirMiPerfil() async {
    final perfil = _perfil ?? await StudentProfile.load();
    if (!mounted) return;
    if (perfil == null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      );
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProfileSetupScreen(
          esEdicion: true,
          perfilExistente: perfil,
        ),
      ),
    );
    if (!mounted) return;
    await _refrescarPerfil();
  }

  // =====================================================================
  //  (4-oct-2026) GRUPOS EN CUADRÍCULA, COMO CARPETAS DE iPHONE.
  //  Antes cada grupo era un ExpansionTile a todo lo ancho y nacía abierto:
  //  la pantalla era una sola columna larga. Ahora cada grupo es una
  //  tarjeta-widget (2 columnas en celular, 3 en tableta, 4 en computadora)
  //  y, al tocarla, sus opciones se abren en un panel sobre la pantalla, en
  //  cuadrícula, sin empujar las demás tarjetas. Las opciones son
  //  EXACTAMENTE las mismas tarjetas (_MenuCard) con su misma acción.
  // =====================================================================
  _Carpeta _grupoMenu(String titulo, String subtitulo, IconData icono,
          List<Widget> hijos) =>
      _Carpeta(titulo, subtitulo, icono, hijos);

  /// Las tarjetas sueltas de un grupo: cada fila trae una o dos _MenuCard
  /// (los espaciadores sobran en la cuadrícula).
  List<_MenuCard> _cartasDe(List<Widget> hijos) {
    final out = <_MenuCard>[];
    for (final h in hijos) {
      if (h is _MenuCard) {
        out.add(h);
      } else if (h is Row) {
        for (final c in h.children) {
          if (c is _MenuCard) out.add(c);
        }
      }
    }
    return out;
  }

  /// 2 columnas en celular, 3 en tableta y 4 en computadora.
  int _columnasPara(double ancho) => ancho < 600 ? 2 : (ancho < 1024 ? 3 : 4);

  Widget _rejillaGrupos(List<_Carpeta> carpetas) {
    return LayoutBuilder(builder: (ctx, cons) {
      final cols = _columnasPara(cons.maxWidth);
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
            child: Text('MÁS OPCIONES',
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                    color: cessumMuted(context))),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: carpetas.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              mainAxisExtent: 172,
            ),
            itemBuilder: (_, i) => _tarjetaCarpeta(carpetas[i]),
          ),
        ]),
      );
    });
  }

  /// La tarjeta-widget del grupo: ícono grande, número de opciones, vista
  /// previa de sus íconos (como una carpeta), título corto y una línea.
  Widget _tarjetaCarpeta(_Carpeta g) {
    final cartas = _cartasDe(g.hijos);
    return Material(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(24),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => _abrirCarpeta(g),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: cessumRed.withValues(alpha: 0.10)),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 14,
                  offset: const Offset(0, 4)),
            ],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: cessumRed.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(g.icono, color: cessumRed, size: 27),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: cessumGold.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('${cartas.length}',
                    style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: cessumGold)),
              ),
            ]),
            const SizedBox(height: 10),
            // Vista previa de la carpeta: los íconos de sus primeras opciones.
            Row(children: [
              for (final c in cartas.take(4))
                Container(
                  width: 24,
                  height: 24,
                  margin: const EdgeInsets.only(right: 5),
                  decoration: BoxDecoration(
                    color: cessumRed.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Icon(c.icon, size: 14, color: cessumRed.withValues(alpha: 0.75)),
                ),
              if (cartas.length > 4)
                Text('+${cartas.length - 4}',
                    style: TextStyle(fontSize: 11, color: cessumMuted(context), fontWeight: FontWeight.w700)),
            ]),
            const Spacer(),
            Text(g.titulo,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: cessumInk(context))),
            const SizedBox(height: 2),
            Text(g.subtitulo,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
          ]),
        ),
      ),
    );
  }

  /// Abre el grupo como carpeta: un panel sobre la pantalla (con el fondo
  /// desenfocado) y sus opciones en cuadrícula. Al elegir una opción, la
  /// carpeta se cierra y se abre la pantalla de siempre.
  void _abrirCarpeta(_Carpeta g) {
    final cartas = _cartasDe(g.hijos);
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Cerrar ${g.titulo}',
      barrierColor: Colors.black.withValues(alpha: 0.35),
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (dCtx, _, __) {
        final tam = MediaQuery.of(dCtx).size;
        final ancho = tam.width.clamp(0.0, 760.0) - 32;
        final cols = ancho < 520 ? 2 : (ancho < 700 ? 3 : 4);
        return BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 7, sigmaY: 7),
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 760, maxHeight: tam.height * 0.86),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Material(
                    color: Theme.of(dCtx).cardColor,
                    borderRadius: BorderRadius.circular(28),
                    clipBehavior: Clip.antiAlias,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        padding: const EdgeInsets.fromLTRB(18, 16, 8, 12),
                        decoration: BoxDecoration(
                          border: Border(bottom: BorderSide(color: cessumRed.withValues(alpha: 0.10))),
                        ),
                        child: Row(children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: cessumRed.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: Icon(g.icono, color: cessumRed, size: 23),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(g.titulo,
                                  style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800,
                                      color: cessumInk(dCtx))),
                              Text(g.subtitulo,
                                  style: TextStyle(fontSize: 12, color: cessumMuted(dCtx))),
                            ]),
                          ),
                          IconButton(
                            tooltip: 'Cerrar',
                            onPressed: () => Navigator.pop(dCtx),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ]),
                      ),
                      Flexible(
                        child: GridView.builder(
                          shrinkWrap: true,
                          padding: const EdgeInsets.all(14),
                          itemCount: cartas.length,
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: cols,
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                            mainAxisExtent: 124,
                          ),
                          // Cada celda es una fila con UNA tarjeta: _MenuCard se
                          // envuelve sola en Expanded y necesita un Row.
                          itemBuilder: (_, i) {
                            final c = cartas[i];
                            return Row(children: [
                              _MenuCard(
                                icon: c.icon,
                                label: c.label,
                                color: c.color,
                                onTap: () {
                                  Navigator.pop(dCtx);
                                  c.onTap();
                                },
                              ),
                            ]);
                          },
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (_, anim, __, child) {
        final curva = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curva,
          child: ScaleTransition(scale: Tween(begin: 0.92, end: 1.0).animate(curva), child: child),
        );
      },
    );
  }

  /// (4-oct-2026) EL BUSCADOR, PROTAGONISTA: grande, arriba, siempre visible
  /// (queda fijo bajo el encabezado) y con sugerencias tocables.
  static const List<String> _sugerencias = [
    'Constancia', 'Pago', 'Calificaciones', 'Horario', 'Credencial',
    'Baja', 'Factura', 'Titulación',
  ];

  Widget _buscadorPrincipal() {
    return Container(
      color: cessumBg(context),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                  color: cessumRed.withValues(alpha: 0.10),
                  blurRadius: 16,
                  offset: const Offset(0, 5)),
            ],
          ),
          child: TextField(
            controller: _buscaCtrl,
            onChanged: (v) => setState(() => _q = v),
            textInputAction: TextInputAction.search,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              hintText: '¿Qué necesitas hacer hoy?',
              hintStyle: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w500, color: cessumMuted(context)),
              prefixIcon: const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Icon(Icons.search_rounded, color: cessumRed, size: 26),
              ),
              suffixIcon: _q.trim().isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Borrar',
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () => setState(() {
                        _buscaCtrl.clear();
                        _q = '';
                      }),
                    ),
              filled: true,
              fillColor: Theme.of(context).cardColor,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide(color: cessumRed.withValues(alpha: 0.18)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide(color: cessumRed.withValues(alpha: 0.18)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: const BorderSide(color: cessumRed, width: 1.6),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 34 * MediaQuery.textScalerOf(context).scale(1.0),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _sugerencias.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (_, i) {
              final s = _sugerencias[i];
              final activa = _normBusca(_q.trim()) == _normBusca(s);
              return ActionChip(
                label: Text(s),
                labelStyle: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: activa ? Colors.white : cessumRed),
                backgroundColor: activa ? cessumRed : cessumRed.withValues(alpha: 0.07),
                side: BorderSide(color: cessumRed.withValues(alpha: activa ? 1 : 0.15)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() {
                  _buscaCtrl.text = s;
                  _q = s;
                }),
              );
            },
          ),
        ),
      ]),
    );
  }

  // ---- BUSCADOR DE RECURSOS DEL MENÚ ----
  final _buscaCtrl = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _hoyTimer?.cancel();
    _buscaCtrl.dispose();
    super.dispose();
  }

  // (ago-5) SEMÁFORO FINANCIERO permanente: verde al corriente, dorado con
  // pago próximo, guinda vencido. Tocarlo abre Pagos. Reasegura al que está
  // al día y le pone fecha al que no — sin abrir ninguna pantalla.
  Widget _chipFinanzas() {
    final fz = _hoy?['finanzas'];
    if (fz is! Map) return const SizedBox.shrink();
    final estado = '${fz['estado'] ?? ''}';
    final detalle = '${fz['detalle'] ?? ''}';
    if (detalle.isEmpty) return const SizedBox.shrink();
    late final Color color;
    late final String texto;
    late final IconData icono;
    if (estado == 'vencido') {
      color = cessumRed;
      icono = Icons.error_outline;
      texto = '⚠ $detalle — regularízate para evitar suspensión';
    } else if (estado == 'proximo') {
      color = const Color(0xFF8A5A0F);
      icono = Icons.schedule;
      texto = '💳 $detalle';
    } else {
      color = const Color(0xFF1E8E3E);
      icono = Icons.verified;
      texto = '✓ Al corriente en tus pagos';
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PagosHubScreen()),
        ),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: double.infinity,
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.45)),
          ),
          child: Row(children: [
            Icon(icono, size: 16, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(texto,
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: color)),
            ),
            Icon(Icons.chevron_right, size: 16, color: color),
          ]),
        ),
      ),
    );
  }

  // (ago-5) TARJETA HOY: la clase de hoy con cuenta regresiva y botón único
  // "Entrar a clase", tareas que vencen pronto y el próximo pago. Un vistazo
  // al abrir la app y el alumno sabe su día.
  Future<void> _cargarHoy() async {
    final p = _perfil;
    if (p == null || p.matricula.isEmpty) return;
    try {
      final r = await http_eval
          .get(Uri.parse(
              '$guardianUrl?accion=alumno_hoy&matricula=${Uri.encodeComponent(p.matricula)}'))
          .timeout(const Duration(seconds: 45));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] == true && mounted) {
        setState(() => _hoy = d);
        _hoyTimer?.cancel();
        _hoyTimer = Timer.periodic(const Duration(minutes: 1), (_) {
          if (mounted) setState(() {});
        });
      }
    } catch (_) {}
  }

  // 'HH:MM' inicial (y final si existe) de cadenas tipo "17:00 a 19:00".
  List<DateTime?> _rangoHoraHoy(String hora) {
    final ms = RegExp(r'(\d{1,2}):(\d{2})').allMatches(hora).toList();
    if (ms.isEmpty) return [null, null];
    final ahora = DateTime.now();
    DateTime arma(RegExpMatch m) => DateTime(ahora.year, ahora.month,
        ahora.day, int.parse(m.group(1)!), int.parse(m.group(2)!));
    return [arma(ms.first), ms.length > 1 ? arma(ms[1]) : null];
  }

  Widget _tarjetaHoy() {
    final h = _hoy;
    if (h == null) return const SizedBox.shrink();
    final clases = ((h['clases'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final tareas = ((h['tareas'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final pago = h['pago'] is Map
        ? Map<String, dynamic>.from(h['pago'] as Map)
        : null;
    if (clases.isEmpty && tareas.isEmpty && pago == null) {
      return const SizedBox.shrink();
    }
    const dias = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes',
      'sábado', 'domingo'];
    const meses = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
      'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];
    final n = DateTime.now();
    final fecha =
        '${dias[n.weekday - 1]} ${n.day} de ${meses[n.month - 1]}';
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: cessumRed.withValues(alpha: 0.45), width: 1.4),
        boxShadow: [
          BoxShadow(
              color: cessumRed.withValues(alpha: 0.07),
              blurRadius: 10,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: const BoxDecoration(
              color: cessumRed,
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(13)),
            ),
            child: Text('HOY · $fecha',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final c in clases) _claseHoy(c),
                if (clases.isEmpty &&
                    (tareas.isNotEmpty || pago != null))
                  const Padding(
                    padding: EdgeInsets.only(bottom: 6),
                    child: Text('Hoy no tienes clase programada.',
                        style: TextStyle(
                            fontSize: 12, color: Colors.black54)),
                  ),
                for (final t in tareas)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: InkWell(
                      onTap: () => Helpers.abrirUrlExterna(
                          'https://aula.cessum.mx/my/', context),
                      child: Text(
                        '📌 ${t['tarea']} · ${t['yaVencio'] == true ? 'VENCIÓ' : 'vence'} ${t['vence']}',
                        style: TextStyle(
                            fontSize: 12,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                            color: t['yaVencio'] == true
                                ? cessumRed
                                : Colors.black87),
                      ),
                    ),
                  ),
                if (pago != null)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: (pago['dias'] as num) < 0
                          ? cessumRed.withValues(alpha: 0.09)
                          : cessumGold.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      (pago['dias'] as num) < 0
                          ? '💳 ${pago['concepto']} — VENCIDO desde ${pago['vence']}'
                          : '💳 ${pago['concepto']}'
                              '${'${pago['monto']}'.isNotEmpty ? ' (\$${pago['monto']})' : ''} — '
                              '${(pago['dias'] as num) == 0 ? 'vence HOY' : 'vence en ${pago['dias']} día(s)'}',
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: (pago['dias'] as num) < 0
                              ? cessumRed
                              : const Color(0xFF8A5A0F)),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _claseHoy(Map<String, dynamic> c) {
    final rango = _rangoHoraHoy('${c['hora'] ?? ''}');
    final ini = rango[0];
    final fin = rango[1];
    final ahora = DateTime.now();
    String estado = '';
    bool destacar = false;
    if (ini != null) {
      final d = ini.difference(ahora);
      final enCurso =
          ahora.isAfter(ini) && (fin == null || ahora.isBefore(fin));
      if (enCurso) {
        estado = '🔴 EN CURSO';
        destacar = true;
      } else if (d.inMinutes >= 0) {
        destacar = d.inMinutes <= 15;
        estado = d.inHours > 0
            ? 'empieza en ${d.inHours} h ${d.inMinutes % 60} min'
            : 'empieza en ${d.inMinutes} min';
      } else if (fin != null && ahora.isAfter(fin)) {
        estado = 'concluyó';
      }
    }
    final link = '${c['linkSesion'] ?? ''}'.isNotEmpty
        ? '${c['linkSesion']}'
        : '${c['linkAula'] ?? ''}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${c['materia']}',
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w800)),
          Text(
              '${c['docente']}'
              '${'${c['hora'] ?? ''}'.isNotEmpty ? ' · ${c['hora']}' : ''}'
              '${estado.isNotEmpty ? '  ·  $estado' : ''}',
              style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  fontWeight:
                      destacar ? FontWeight.w800 : FontWeight.w500,
                  color: destacar ? cessumRed : Colors.black54)),
          if (link.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: SizedBox(
                width: double.infinity,
                child: destacar
                    ? ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: cessumRed,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(0, 40)),
                        onPressed: () =>
                            Helpers.abrirUrlExterna(link, context),
                        icon: const Icon(Icons.videocam, size: 18),
                        label: const Text('Entrar a clase',
                            style:
                                TextStyle(fontWeight: FontWeight.w800)),
                      )
                    : OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                            foregroundColor: cessumRed,
                            side: const BorderSide(color: cessumRed),
                            minimumSize: const Size(0, 38)),
                        onPressed: () =>
                            Helpers.abrirUrlExterna(link, context),
                        icon: const Icon(Icons.videocam, size: 17),
                        label: const Text('Entrar a clase'),
                      ),
              ),
            ),
        ],
      ),
    );
  }

  // Normaliza para buscar: minúsculas y sin acentos.
  String _normBusca(String s) {
    var t = s.toLowerCase();
    const con = 'áéíóúüñ';
    const sin = 'aeiouun';
    for (var i = 0; i < con.length; i++) {
      t = t.replaceAll(con[i], sin[i]);
    }
    return t;
  }

  // Catálogo de TODAS las opciones del menú con su descripción (también
  // se busca por ella). Cada acción es EXACTAMENTE la de su tarjeta.
  List<_OpcionMenu> _catalogoOpciones() {
    return [
      // (ago-27) Si está dado de baja, esto va ANTES que nada: es lo único
      // que le sirve del menú hasta que se reintegre.
      if (_puedeReingresar)
        _OpcionMenu('Volver a estudiar',
            'Estás dado de baja. Aquí puedes solicitar tu reintegración.',
            Icons.restart_alt,
            () => Navigator.push(
            context,
            MaterialPageRoute(
            builder: (_) => ReingresoAlumnoScreen(
                matricula: _perfil?.matricula ?? ''),
            ),
            )),
      // (ago-25) EL CHAT VA PRIMERO.
      // Estaba a mitad de una lista de treinta opciones, y una alumna que
      // busca a quién preguntarle no baja treinta renglones: escribe por
      // WhatsApp al primero que le conteste. Es el canal que la institución
      // declara como único, así que tiene que ser el más fácil de encontrar.
      _OpcionMenu('Chat con mi docente',
          'Único canal para dudas. Tu profesor responde en 24 horas.',
          Icons.forum_outlined,
          () => Navigator.push(
          context,
          MaterialPageRoute(
          builder: (_) => const MensajesScreen(),
          ),
          )),
      _OpcionMenu('Mis clases y links de mis sesiones',
          'Tus clases de hoy y el link directo para entrar a cada sesión.',
          Icons.video_camera_front,
          () => Navigator.push(
          context,
          MaterialPageRoute(
          builder: (_) => const MisClasesScreen(),
          ),
          )),
      _OpcionMenu('Becas',
          '¿Cuentas con una beca? Regístrala y sube tu resolución.',
          Icons.school,
          () => Navigator.push(
          context,
          MaterialPageRoute(
          builder: (_) => const BecasScreen(),
          ),
          )),
      _OpcionMenu('Grabaciones de clase y mi asistencia',
          'Las grabaciones de tus sesiones en vivo y tu contador de asistencia.',
          Icons.ondemand_video,
          () => Navigator.push(
          context,
          MaterialPageRoute(
          builder: (_) => const GrabacionesClaseScreen(),
          ),
          )),
      _OpcionMenu('Aula virtual (Moodle)',
          'Entra a Moodle: tus cursos, tareas y materiales.',
          Icons.school,
          () => Navigator.push(
          context,
          MaterialPageRoute(
          builder: (_) => const MiAulaScreen(),
          ),
          )),
      _OpcionMenu('Pagos',
          'Consulta tu plan de pagos, montos y realiza tus pagos.',
          Icons.receipt_long,
          () => Navigator.push(
          context,
          MaterialPageRoute(
          builder: (_) => const PagosHubScreen(),
          ),
          )),
      _OpcionMenu('Asistente CESSUM',
          'Chatea con el asistente y resuelve tus dudas al momento.',
          Icons.auto_awesome,
          () {
          final p = _perfil;
          if (p == null) {
          ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
          content: Text(
          'Completa tu perfil para usar el asistente'),
          ),
          );
          return;
          }
          Navigator.push(
          context,
          MaterialPageRoute(
          builder: (_) => AsistenteAlumnoScreen(perfil: p),
          ),
          );
          }),
      _OpcionMenu('Mis pendientes',
          'Todo lo que tienes pendiente: tareas, pagos y trámites.',
          Icons.checklist,
          () async {
          final p = _perfil;
          if (p == null || p.matricula.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
          content: Text(
          'Completa tu perfil para ver tus pendientes'),
          ),
          );
          return;
          }
          final correo =
          (await SessionStore.validEmail()) ?? '';
          if (!mounted) return;
          Navigator.push(
          context,
          MaterialPageRoute(
          builder: (_) => MisPendientesScreen(
          matricula: p.matricula,
          nombre: p.nombreCompleto,
          correo: correo,
          ),
          ),
          );
          }),
      _OpcionMenu('Mis materias',
          'Tus materias en curso y las que vienen: fechas, horarios, quiénes serán tus profesores y conoce a tu profesor actual.',
          Icons.menu_book,
          () async {
          final p = _perfil;
          if (p == null || p.matricula.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
          content: Text(
          'Completa tu perfil para ver tus materias'),
          ),
          );
          return;
          }
          Navigator.push(
          context,
          MaterialPageRoute(
          builder: (_) => MateriasAlumnoScreen(matricula: p.matricula),
          ),
          );
          }),
      _OpcionMenu('Convenios',
          'Convenios institucionales dirigidos a ti: léelos completos y fírmalos con tu firma digital.',
          Icons.history_edu,
          () async {
          final p = _perfil;
          if (p == null || p.matricula.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
          content: Text(
          'Completa tu perfil para ver tus convenios'),
          ),
          );
          return;
          }
          Navigator.push(
          context,
          MaterialPageRoute(
          builder: (_) => ConveniosAlumnoScreen(matricula: p.matricula),
          ),
          );
          }),
      _OpcionMenu('Mi horario',
          'Días, horas y vigencia de cada una de tus materias.',
          Icons.calendar_month,
          () async {
          final p = _perfil;
          if (p == null) {
          ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
          content: Text(
          'Completa tu perfil para ver tu horario'),
          ),
          );
          return;
          }
          Navigator.push(
          context,
          MaterialPageRoute(
          builder: (_) => MiHorarioScreen(perfil: p),
          ),
          );
          }),
      _OpcionMenu('Calendario',
          'Calendario institucional con sesiones y fechas importantes.',
          Icons.event,
          () => Navigator.push(
          context,
          MaterialPageRoute(
          builder: (_) => const CalendarioScreen(),
          ),
          )),
      _OpcionMenu('Tareas y entregas',
          'Tareas de tus cursos con su fecha de entrega.',
          Icons.assignment_turned_in,
          () async {
          final p = _perfil;
          if (p == null) {
          ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
          content: Text(
          'Completa tu perfil para ver tus tareas'),
          ),
          );
          return;
          }
          Navigator.push(
          context,
          MaterialPageRoute(
          builder: (_) => TareasAlumnoScreen(perfil: p),
          ),
          );
          }),
      _OpcionMenu('Recursos y materiales',
          'Materiales y recursos que comparten tus maestros.',
          Icons.folder_shared,
          () async {
          final p = _perfil;
          if (p == null) {
          ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
          content: Text(
          'Completa tu perfil para ver tus recursos'),
          ),
          );
          return;
          }
          Navigator.push(
          context,
          MaterialPageRoute(
          builder: (_) =>
          RecursosAlumnoScreen(perfil: p),
          ),
          );
          }),
      _OpcionMenu('Avisos de maestros',
          'Avisos que tus maestros envían a tu grupo.',
          Icons.campaign,
          () async {
          final p = _perfil;
          if (p == null) {
          ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
          content: Text(
          'Completa tu perfil para ver tus avisos'),
          ),
          );
          return;
          }
          Navigator.push(
          context,
          MaterialPageRoute(
          builder: (_) => AvisosAlumnoScreen(perfil: p),
          ),
          );
          }),
      _OpcionMenu('Mis recordatorios',
          'Crea recordatorios personales de clases y entregas.',
          Icons.notifications_active,
          () => Navigator.push(
          context,
          MaterialPageRoute(
          builder: (_) => RecordatoriosScreen(
          matricula: _perfil?.matricula ?? ''),
          ),
          )),
      _OpcionMenu('Tutorías y asesorías',
          'Solicita tutoría o asesoría con tus maestros.',
          Icons.support_agent,
          () {
          final p = _perfil;
          if (p == null) {
          ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
          content: Text(
          'Completa tu perfil para ver tus tutorías'),
          ),
          );
          return;
          }
          Navigator.push(
          context,
          MaterialPageRoute(
          builder: (_) =>
          TutoriasAlumnoScreen(perfil: p),
          ),
          );
          }),
      _OpcionMenu('Mis calificaciones',
          'Tus calificaciones por materia y periodo.',
          Icons.grading,
          () {
          final p = _perfil;
          if (p == null || p.matricula.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
          content: Text(
          'Completa tu perfil para ver tus calificaciones'),
          ),
          );
          return;
          }
          Navigator.push(
          context,
          MaterialPageRoute(
          builder: (_) => MisCalificacionesScreen(
          matricula: p.matricula),
          ),
          );
          }),
      _OpcionMenu('Mi boleta',
          'Descarga tu boleta oficial de calificaciones.',
          Icons.receipt_long,
          () => Navigator.push(
          context,
          MaterialPageRoute(
          builder: (_) =>
          MiBoletaScreen(perfil: _perfil),
          ),
          )),
      _OpcionMenu('Mi progreso académico',
          'Gráfica de tu desempeño a lo largo del programa.',
          Icons.assessment,
          () => Navigator.push(
          context,
          MaterialPageRoute(
          builder: (_) => const MiProgresoScreen(),
          ),
          )),
      _OpcionMenu('Mi avance del plan',
          'Materias aprobadas frente a tu plan de estudios.',
          Icons.donut_large,
          () {
          final p = _perfil;
          if (p == null) {
          ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
          content: Text(
          'Completa tu perfil para ver tu avance'),
          ),
          );
          return;
          }
          Navigator.push(
          context,
          MaterialPageRoute(
          builder: (_) => const AvancePlanScreen(),
          ),
          );
          }),
      // (8-sep) EL CONCENTRADO POR GRUPO, BUSCABLE.
      // Existía desde antes pero vivía dos niveles adentro —menú, Herramientas
      // de administración, y ahí una tarjeta más—, y el buscador no lo
      // encontraba porque solo indexa este catálogo. Una rejilla de alumnos por
      // materias que escribe en la base real es de las herramientas más útiles
      // que hay, y estaba enterrada.
      _OpcionMenu('Concentrado por grupo',
          'Matriz de alumnos por materias: revisa el grupo completo y edita calificaciones.',
          Icons.grid_on,
          () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const MatrizGrupoScreen())),
          soloAdmin: true),
      _OpcionMenu('Calificaciones por grupo',
          'Lo mismo que el concentrado: rejilla del grupo para capturar y corregir.',
          Icons.table_chart,
          () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const MatrizGrupoScreen())),
          soloAdmin: true),
      // (22-sep) Cuántos alumnos sostienen un grupo y qué deja, antes de abrirlo.
      _OpcionMenu('Simulador de grupos',
          'Ingreso, costo docente, punto de equilibrio y qué pasa si se cae una parte, con las bajas reales.',
          Icons.calculate_outlined,
          () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const SimuladorScreen())),
          soloAdmin: true),
      // (22-sep) Qué solicitud de inscripción está a medias y qué le falta.
      _OpcionMenu('Altas de inscripción',
          'Cada solicitud con sus pasos comprobados: revisión, cuenta, matrícula, padrón, grupo, aula y bienvenida.',
          Icons.fact_check_outlined,
          () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const AltasScreen())),
          soloAdmin: true),
      // (22-sep) Riesgo por alumno y diagnóstico por materia, con razones.
      _OpcionMenu('Señales académicas',
          'A quién se le está apagando la participación y qué materias hunden la permanencia, con las razones.',
          Icons.insights_outlined,
          () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const SenalesScreen())),
          soloAdmin: true),
      // (22-sep) Un solo lugar donde ver si todo está corriendo.
      _OpcionMenu('Salud del sistema',
          'Disparadores, colas pendientes, clases y datos: qué está detenido y cómo se arregla.',
          Icons.monitor_heart_outlined,
          () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const SaludScreen())),
          soloAdmin: true),
      // (22-sep) Estados de cuenta del banco con análisis de IA.
      if (_esFinanzas)
        _OpcionMenu('Finanzas · estados de cuenta',
            'Sube el estado de cuenta de BBVA: gastos por categoría, histórico, alertas y asistente de IA.',
            Icons.account_balance,
            () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const FinanzasScreen())),
            soloAdmin: true),
      _OpcionMenu('Plan de estudios',
          'El mapa completo de materias de tu programa.',
          Icons.menu_book,
          () {
          final prog = _perfil?.programa;
          Navigator.push(
          context,
          MaterialPageRoute(
          builder: (_) => CartasDescriptivasScreen(
          programaFijo: (prog == null || prog.isEmpty)
          ? null
          : prog,
          ),
          ),
          );
          }),
      _OpcionMenu('Calculadora de promedio',
          'Calcula tu promedio y simula escenarios de calificación.',
          Icons.calculate,
          () => Navigator.push(
          context,
          MaterialPageRoute(
          builder: (_) =>
          const CalculadoraPromedioScreen(),
          ),
          )),
      _OpcionMenu('Mi perfil de aprendizaje',
          'Descubre tu estilo y hábitos de aprendizaje.',
          Icons.psychology,
          () => Navigator.push(
          context,
          MaterialPageRoute(
          builder: (_) => PerfilAprendizajeScreen(
          matricula: _perfil?.matricula ?? '',
          nombre: _perfil?.nombreCompleto ?? '',
          programa: _perfil?.programa ?? '',
          generacion: _perfil?.generacion ?? '',
          ),
          ),
          )),
      // (ago-25) «Aprendizaje de mis grupos» SALIÓ del catálogo.
      // El catálogo alimenta el buscador y NO filtra por rol, así que un
      // alumno llegaba a una pantalla de docente que le pedía grupos
      // asignados —que nunca va a tener— y le respondía «verifica con
      // Vicerrectoría tus asignaciones»: un mensaje falso y preocupante.
      // La pantalla sigue existiendo y se abre desde el panel del docente.
      // (ago-20) Panel de Vicerrectoría: quiénes recursan, quién pagó y a
      // quién falta matricular. Va junto al del alumno porque es el mismo
      // tema visto desde el otro lado.
      // Panel de Vicerrectoría: sale del buscador del alumno. Antes aparecía
      // al escribir «recursamiento» y lo llevaba a una lista con los datos
      // de sus compañeros.
      // (ago-28) El panel de Vicerrectoría SE MUDÓ al menú de
      // administración, en «Calificaciones y captura». Aquí quedaba
      // escondido: solo se llegaba escribiendo la palabra en el buscador,
      // y en el menú de admin —donde uno lo busca— no aparecía.
      // Ver admin_preview_screen.dart · _tarjetaRecursamientos().
      // (25-sep) Mi ruta al título: dónde voy y qué me falta para titularme.
      _OpcionMenu('Mi ruta al título',
          'Dónde vas, qué te falta para egresar y titularte, cuándo terminas y cuánto cuesta. Con coach.',
          Icons.route,
          () {
          if (_perfil == null) {
          ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Completa tu perfil para ver tu ruta')),
          );
          return;
          }
          Navigator.push(context, MaterialPageRoute(builder: (_) => const MiRutaScreen()));
          }),
      _OpcionMenu('Recursamientos',
          'Solicita recursar una materia reprobada.',
          Icons.replay_circle_filled,
          () async {
          final p = _perfil;
          if (p == null) {
          ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
          content: Text(
          'Completa tu perfil para ver tus recursamientos'),
          ),
          );
          return;
          }
          final correo =
          await SessionStore.validEmail() ?? '';
          if (!mounted) return;
          Navigator.push(
          context,
          MaterialPageRoute(
          builder: (_) => RecursamientosScreen(
          matricula: p.matricula,
          correo: correo,
          nombre: p.nombreCompleto,
          programa: p.programa,
          generacion: p.generacion,
          ),
          ),
          );
          }),
      _OpcionMenu('Trámites y documentos oficiales',
          'Solicita constancias, kardex y documentos oficiales.',
          Icons.description,
          () {
          final p = _perfil;
          if (p == null) {
          ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
          content: Text(
          'Completa tu perfil para generar documentos'),
          ),
          );
          return;
          }
          Navigator.push(
          context,
          MaterialPageRoute(
          builder: (_) =>
          const SolicitudTramitesScreen(),
          ),
          );
          }),
      _OpcionMenu('Mis trámites',
          'El estatus de los trámites que has solicitado.',
          Icons.fact_check,
          () {
          final p = _perfil;
          if (p == null || p.matricula.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
          content: Text(
          'Completa tu perfil para ver tus trámites'),
          ),
          );
          return;
          }
          Navigator.push(
          context,
          MaterialPageRoute(
          builder: (_) => MisTramitesScreen(
          matricula: p.matricula),
          ),
          );
          }),
      _OpcionMenu('Mis documentos',
          'Tus documentos emitidos, listos para descargar.',
          Icons.folder_shared,
          () async {
          final p = _perfil;
          if (p == null) {
          ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
          content: Text(
          'Completa tu perfil para ver tus documentos'),
          ),
          );
          return;
          }
          Navigator.push(
          context,
          MaterialPageRoute(
          builder: (_) => MisDocumentosScreen(
          matricula: p.matricula),
          ),
          );
          }),
      _OpcionMenu('Reinscripción',
          'Formulario de reinscripción al siguiente periodo.',
          Icons.refresh,
          () => Helpers.abrirUrlExterna(
          formReinscripcionUrl,
          context,
          )),
      _OpcionMenu('Solicitud de factura',
          'Pide la factura de tus pagos.',
          Icons.receipt_long,
          () => Navigator.push(
          context,
          MaterialPageRoute(
          builder: (_) =>
          const SolicitudFacturaScreen(),
          ),
          )),
      _OpcionMenu('Justificación de faltas',
          'Envía el justificante de una inasistencia con tu evidencia.',
          Icons.event_busy,
          () => Navigator.push(
          context,
          MaterialPageRoute(
          builder: (_) =>
          const JustificacionFaltasScreen(),
          ),
          )),
      _OpcionMenu('Adaptación de modalidad',
          'Solicita un cambio temporal de modalidad de estudio.',
          Icons.sync_alt,
          () => Navigator.push(
          context,
          MaterialPageRoute(
          builder: (_) =>
          const SolicitudAdaptacionModalidadScreen(),
          ),
          )),
      _OpcionMenu('Cambio de programa',
          'Solicita cambiarte de programa académico.',
          Icons.swap_horiz,
          () {
          final p = _perfil;
          if (p == null) {
          ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
          content: Text(
          'Completa tu perfil para solicitar el cambio'),
          ),
          );
          return;
          }
          Navigator.push(
          context,
          MaterialPageRoute(
          builder: (_) =>
          const SolicitudCambioProgramaScreen(),
          ),
          );
          }),
      _OpcionMenu('Solicitar baja',
          'Inicia el trámite de baja temporal o definitiva.',
          Icons.exit_to_app,
          () {
          final p = _perfil;
          if (p == null) {
          ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
          content: Text(
          'Completa tu perfil para solicitar la baja'),
          ),
          );
          return;
          }
          Navigator.push(
          context,
          MaterialPageRoute(
          builder: (_) => const SolicitudBajaScreen(),
          ),
          );
          }),
      _OpcionMenu('Tutor de tesis',
          'Solicita formalmente a tu director de tesis: propones tu tema y firmas tu compromiso de seguimiento.',
          Icons.school_outlined,
          () {
          final p = _perfil;
          if (p == null) {
          ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
          content: Text(
          'Completa tu perfil para solicitar tutor'),
          ),
          );
          return;
          }
          Navigator.push(
          context,
          MaterialPageRoute(
          builder: (_) => SolicitarTutorScreen(matricula: p.matricula),
          ),
          );
          }),
      _OpcionMenu('Mi titulación paso a paso',
          'Tu ruta de titulación: opción, requisitos y ventanillas.',
          Icons.timeline,
          () {
          final p = _perfil;
          if (p == null) {
          ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
          content: Text(
          'Completa tu perfil para ver tu titulación'),
          ),
          );
          return;
          }
          Navigator.push(
          context,
          MaterialPageRoute(
          builder: (_) => const MiTitulacionScreen(),
          ),
          );
          }),
      // (8-sep) «Mi expediente de titulación» dejó de ser una entrada propia:
      // sus documentos vivían en una hoja que solo se copiaba a Titulación al
      // presentar la solicitud, y después de ese momento entregar ahí no
      // llegaba a revisión.
      // (14-sep) VUELVE AL MENÚ. Al esconderla se perdió el único lugar donde
      // el alumno veía lo que ya había subido, y mucha gente la usaba para
      // adelantar documentos antes de que abriera la ventanilla. El Guardián
      // ahora escribe en las dos hojas cuando ya hay solicitud, así que la
      // pantalla sirve en cualquier momento y nada queda varado.
      _OpcionMenu('Mi expediente de titulación',
          'Sube tus documentos desde ahora y consulta los que ya entregaste.',
          Icons.folder_copy,
          () async {
          final p = _perfil;
          if (p == null || p.matricula.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
          content: Text(
          'Completa tu perfil para ver tu expediente'),
          ),
          );
          return;
          }
          Navigator.push(
          context,
          MaterialPageRoute(
          builder: (_) => MiExpedienteTitulacionScreen(perfil: p),
          ),
          );
          }),
      _OpcionMenu('Mi tesis (convenio y avances)',
          'Convenio de tesis, director y registro de avances.',
          Icons.school,
          () async {
          final p = _perfil;
          if (p == null || p.matricula.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
          content: Text(
          'Completa tu perfil para ver tu tesis'),
          ),
          );
          return;
          }
          final correo =
          (await SessionStore.validEmail()) ?? '';
          if (!mounted) return;
          Navigator.push(
          context,
          MaterialPageRoute(
          builder: (_) => TesisConvenioScreen(
          matricula: p.matricula,
          nombre: p.nombreCompleto,
          correo: correo,
          rol: 'alumno',
          ),
          ),
          );
          }),
      _OpcionMenu('Mesa de ayuda',
          'Levanta un ticket de soporte y dale seguimiento.',
          Icons.support_agent,
          () {
          final p = _perfil;
          if (p == null) {
          ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
          content: Text(
          'Completa tu perfil para usar la Mesa de ayuda'),
          ),
          );
          return;
          }
          Navigator.push(
          context,
          MaterialPageRoute(
          builder: (_) => MesaAyudaScreen(perfil: p),
          ),
          );
          }),
      _OpcionMenu('Eventos',
          'Eventos institucionales e inscripciones.',
          Icons.event_available,
          () async {
          final p = _perfil;
          if (p == null) {
          ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
          content: Text(
          'Completa tu perfil para ver tus eventos'),
          ),
          );
          return;
          }
          Navigator.push(
          context,
          MaterialPageRoute(
          builder: (_) => EventosScreen(perfil: p),
          ),
          );
          }),
      _OpcionMenu('Buzón de sugerencias',
          'Envía sugerencias identificándote para recibir respuesta.',
          Icons.feedback,
          () {
          final p = _perfil;
          if (p == null || p.matricula.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
          content: Text(
          'Completa tu perfil para usar el buzón'),
          ),
          );
          return;
          }
          Navigator.push(
          context,
          MaterialPageRoute(
          builder: (_) => BuzonScreen(
          matricula: p.matricula,
          nombre: p.nombreCompleto,
          ),
          ),
          );
          }),
      _OpcionMenu('Buzón anónimo',
          'Envía comentarios de forma totalmente anónima.',
          Icons.voice_over_off,
          () => Navigator.push(
          context,
          MaterialPageRoute(
          builder: (_) => const BuzonScreen(),
          ),
          )),
      _OpcionMenu('Convocatorias vigentes',
          'Convocatorias abiertas de CESSUM.',
          Icons.campaign,
          () => Helpers.abrirUrlExterna(
          convocatoriasUrl,
          context,
          )),
      // (8-sep) Retirada del buscador: «Recomienda y gana» era el segundo
      // programa de referidos y emitía códigos que administración buscaba en
      // otra hoja. Queda solo «Invita a alguien».
      _OpcionMenu('Juegos',
          'Juegos educativos para repasar y aprender.',
          Icons.sports_esports,
          () {
          final p = _perfil;
          if (p == null) {
          ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
          content:
          Text('Completa tu perfil para jugar'),
          ),
          );
          return;
          }
          Navigator.push(
          context,
          MaterialPageRoute(
          builder: (_) => JuegosHubScreen(perfil: p),
          ),
          );
          }),
      _OpcionMenu('Mi perfil',
          'Tus datos personales y de contacto.',
          Icons.manage_accounts,
          _abrirMiPerfil),
      _OpcionMenu('Mi credencial',
          'Tu credencial digital de estudiante.',
          Icons.badge,
          () => Navigator.push(
          context,
          MaterialPageRoute(
          builder: (_) => const MiCredencialScreen(),
          ),
          )),
      _OpcionMenu('Mi firma',
          'Registra tu firma digital para documentos.',
          Icons.draw,
          () => Navigator.push(
          context,
          MaterialPageRoute(
          builder: (_) => FirmaAlumnoScreen(
          matricula: _perfil?.matricula ?? ''),
          ),
          )),
      _OpcionMenu('Guía de bienvenida',
          'Vuelve a ver la guía de bienvenida de la app.',
          Icons.help_outline,
          () =>
          mostrarOnboardingAhora(context, _perfil)),
      _OpcionMenu('Acerca de CESSUM',
          'Misión, visión e historia de CESSUM.',
          Icons.info_outline,
          () => Navigator.push(
          context,
          MaterialPageRoute(
          builder: (_) => const AcercaScreen(),
          ),
          )),
      _OpcionMenu('Contacto y datos útiles',
          'Teléfonos, correos y datos de contacto útiles.',
          Icons.contact_support,
          () => Navigator.push(
          context,
          MaterialPageRoute(
          builder: (_) => const ContactoScreen(),
          ),
          )),
      _OpcionMenu('Identidad CESSUM',
          'Logos, colores y elementos de la identidad CESSUM.',
          Icons.workspace_premium,
          () => Navigator.push(
          context,
          MaterialPageRoute(
          builder: (_) =>
          IdentidadScreen(admin: _esAdmin),
          ),
          )),
      // (ago-19) Referidos. Va arriba en el menú a propósito: es lo que más
      // puede mover la inscripción de la próxima generación, y una entrada
      // enterrada al final no la abre nadie.
      _OpcionMenu('Invita a alguien',
          'Tu recomendación vale más que un anuncio. Y te dan descuento.',
          Icons.volunteer_activism_outlined,
          () => Navigator.push(
          context,
          MaterialPageRoute(
          builder: (_) => const ReferidosScreen(),
          ),
          )),
      // (ago-18) Mensajería. Una sola entrada para alumnos y docentes: el
      // backend decide con quién puede hablar cada quien. Existe para dejar
      // de repartir números de celular.
      // (ago-24) Se llama "Chat con docente" por indicación de Vicerrectoría,
      // y el subtítulo dice el plazo: un canal sin tiempo de respuesta
      // comprometido se siente igual que escribir al vacío.
      _OpcionMenu('Banco de formatos',
          'Formatos institucionales descargables.',
          Icons.folder_copy,
          () => Navigator.push(
          context,
          MaterialPageRoute(
          builder: (_) =>
          FormatosScreen(admin: _esAdmin),
          ),
          )),
      _OpcionMenu('Referencias APA 7',
          'Genera y copia citas y referencias en formato APA 7.',
          Icons.menu_book,
          () => Navigator.push(
          context,
          MaterialPageRoute(
          builder: (_) =>
          const ApaReferenciasScreen(),
          ),
          )),
      _OpcionMenu('Evaluación docente',
          'Evalúa a tus maestros: tu opinión mejora tus clases.',
          Icons.rate_review,
          () async {
          final p = _perfil;
          if (p == null) return;
          await Navigator.push(
          context,
          MaterialPageRoute(
          builder: (_) => EvaluacionDocenteScreen(perfil: p),
          ),
          );
          _cargarEvalPendientes();
          }),
    ];
  }

  /// Palabras relacionadas para el buscador (sin acentos, en minúsculas).
  static const Map<String, List<String>> _relacionadas = {
    'constancia': ['documento', 'tramite', 'oficial', 'certificado', 'kardex'],
    'documento': ['tramite', 'constancia', 'oficial', 'formato'],
    'pago': ['pagos', 'colegiatura', 'mensualidad', 'adeudo', 'factura', 'convenio'],
    'calificacion': ['boleta', 'promedio', 'progreso', 'kardex', 'concentrado'],
    'boleta': ['calificacion', 'promedio', 'progreso'],
    'baja': ['solicitar baja', 'abandonar', 'suspender'],
    'horario': ['clase', 'calendario', 'sesion', 'materia'],
    'clase': ['horario', 'sesion', 'grabacion', 'moodle', 'aula'],
    'credencial': ['identidad', 'perfil', 'foto'],
    'titulo': ['titulacion', 'tesis', 'expediente'],
    'tesis': ['titulacion', 'director', 'expediente'],
    'factura': ['fiscal', 'rfc', 'pago'],
    'tarea': ['entrega', 'actividad', 'recurso'],
    'maestro': ['docente', 'chat', 'mensaje', 'profesor'],
    'profesor': ['docente', 'chat', 'mensaje', 'maestro'],
    'beca': ['descuento', 'apoyo', 'convocatoria'],
    'ayuda': ['mesa de ayuda', 'soporte', 'problema', 'queja', 'contacto'],
    'problema': ['mesa de ayuda', 'queja', 'soporte'],
    'recursar': ['recursamiento', 'reprobada'],
    'reinscripcion': ['inscripcion', 'reinscribir'],
    'falta': ['justificacion', 'asistencia', 'grabacion'],
    'asistencia': ['justificacion', 'falta', 'grabacion'],
  };

  /// La consulta y sus palabras relacionadas («pagos» también activa «pago»).
  List<String> _terminosRelacionados(String q) {
    if (q.length < 3) return const [];
    final out = <String>{};
    _relacionadas.forEach((clave, rel) {
      final toca = q.contains(clave) || clave.startsWith(q) || rel.any((r) => r.startsWith(q) || q.contains(r));
      if (toca) {
        out.add(clave);
        out.addAll(rel);
      }
    });
    out.remove(q);
    return out.toList();
  }

  List<Widget> _resultadosBusqueda() {
    final q = _normBusca(_q.trim());
    // (4-oct-2026) También por PALABRAS RELACIONADAS: «constancia» encuentra
    // trámites y documentos; «pago» encuentra pagos, factura y convenios.
    // Primero lo que coincide en el nombre, luego en la descripción y al
    // final lo encontrado por palabra relacionada.
    final terminos = _terminosRelacionados(q);
    int puntaje(_OpcionMenu o) {
      final n = _normBusca(o.nombre), d = _normBusca(o.descripcion);
      if (n.contains(q)) return 0;
      if (d.contains(q)) return 1;
      if (terminos.any((x) => n.contains(x))) return 2;
      if (terminos.any((x) => d.contains(x))) return 3;
      return 9;
    }
    final res = _catalogoOpciones()
        // Lo que no es suyo, no se le ofrece. Ver la nota en _OpcionMenu.
        .where((o) => !o.soloAdmin || _esAdmin)
        .where((o) => puntaje(o) < 9)
        .toList()
      ..sort((x, y) => puntaje(x).compareTo(puntaje(y)));
    if (res.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: Text(
              'Sin resultados para "${_q.trim()}".\n'
              'Prueba con otra palabra: boleta, constancia, tesis, pagos…',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12.5, color: Colors.black54),
            ),
          ),
        ),
      ];
    }
    return [
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(
          '${res.length} resultado(s)',
          style: const TextStyle(fontSize: 11.5, color: Colors.black54),
        ),
      ),
      for (final o in res) ...[
        Material(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          elevation: 1,
          child: InkWell(
            onTap: o.accion,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: cessumRed.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(o.icono, color: cessumRed, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(o.nombre,
                            style: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 3),
                        Text(o.descripcion,
                            style: const TextStyle(
                                fontSize: 11.5,
                                height: 1.3,
                                color: Colors.black54)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.black38),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
      ],
    ];
  }

  Widget _tarjetaNotificaciones() {
    final hay = _notisNoLeidas > 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: hay ? cessumRed.withValues(alpha: 0.10) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        elevation: hay ? 0 : 1,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            final p = _perfil;
            final correo = (await SessionStore.validEmail()) ?? '';
            if (!mounted) return;
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => NotificacionesScreen(
                  correo: correo,
                  matricula: p?.matricula ?? '',
                ),
              ),
            );
            _cargarNotis();
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(Icons.notifications,
                        color: hay ? cessumRed : Colors.black54, size: 24),
                    if (hay)
                      Positioned(
                        right: -4,
                        top: -4,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(
                              color: cessumRed, shape: BoxShape.circle),
                          constraints: const BoxConstraints(
                              minWidth: 16, minHeight: 16),
                          child: Text('$_notisNoLeidas',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    hay ? 'Tienes $_notisNoLeidas sin leer' : 'Notificaciones',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: hay ? FontWeight.w700 : FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.black38),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _fechaHoyTexto() {
    const dias = [
      'lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado',
      'domingo'
    ];
    const meses = [
      'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio',
      'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'
    ];
    final h = DateTime.now();
    final dia = dias[(h.weekday - 1) % 7];
    final diaCap = dia[0].toUpperCase() + dia.substring(1);
    return '$diaCap ${h.day} de ${meses[h.month - 1]} de ${h.year}';
  }

  // ===== PULSO INSTITUCIONAL (ago-3) =====
  // Micro-pregunta esporádica: cada 3-5 inicios de sesión (umbral
  // aleatorio local). Las de docente alimentan su ranking; las demás,
  // el tablero institucional. Siempre se puede omitir.
  Future<void> _pulsoCheck(dynamic perfil) async {
    try {
      final mat = (perfil?.matricula ?? '').toString();
      if (mat.isEmpty) return;
      final prefs = await SharedPreferences.getInstance();
      var cont = (prefs.getInt('pulso_contador') ?? 0) + 1;
      var umbral = prefs.getInt('pulso_umbral') ?? 0;
      if (umbral < 3) {
        umbral = 3 + Random().nextInt(3); // 3, 4 o 5
        await prefs.setInt('pulso_umbral', umbral);
      }
      if (cont < umbral) {
        await prefs.setInt('pulso_contador', cont);
        return;
      }
      await prefs.setInt('pulso_contador', 0);
      await prefs.setInt('pulso_umbral', 3 + Random().nextInt(3));
      final r = await http_eval
          .get(Uri.parse(
              '$guardianUrl?accion=pulso_pregunta&matricula=${Uri.encodeComponent(mat)}'))
          .timeout(const Duration(seconds: 30));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true || d['pregunta'] == null) return;
      final q = Map<String, dynamic>.from(d['pregunta'] as Map);
      if (!mounted) return;
      _pulsoDialogo(mat, q);
    } catch (_) {}
  }

  void _pulsoDialogo(String mat, Map<String, dynamic> q) {
    final opciones = ((q['opciones'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Container(
          padding: const EdgeInsets.all(18),
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: cessumRed.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10)),
                  child:
                      const Icon(Icons.bolt, color: cessumRed, size: 20),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('PREGUNTA RÁPIDA · 10 segundos',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: cessumRed,
                          letterSpacing: 0.4)),
                ),
              ]),
              const SizedBox(height: 12),
              Text('${q['texto']}',
                  style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      height: 1.35)),
              const SizedBox(height: 14),
              for (final op in opciones)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                          color: cessumRed.withValues(alpha: 0.35)),
                      padding: const EdgeInsets.symmetric(
                          vertical: 11, horizontal: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _pulsoEnviar(mat, q, op);
                    },
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('${op['t']}',
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Ahora no',
                    style:
                        TextStyle(fontSize: 12, color: Colors.black45)),
              ),
              const Text(
                'Tu respuesta es anónima ante tus profesores y nos ayuda '
                'a mejorar la calidad de CESSUM.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10, color: Colors.black38),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pulsoEnviar(
      String mat, Map<String, dynamic> q, Map<String, dynamic> op) async {
    try {
      await http_eval
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'pulso_responder',
                'matricula': mat,
                'preguntaId': q['id'],
                'categoria': q['categoria'],
                'pregunta': q['texto'],
                'respuesta': op['t'],
                'valor': op['v'],
                'docente': q['docente'] ?? '',
                'materia': q['materia'] ?? '',
              }))
          .timeout(const Duration(seconds: 30));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            backgroundColor: Color(0xFF1E8E3E),
            duration: Duration(seconds: 2),
            content: Text('¡Gracias! Tu opinión construye CESSUM. 🎓')));
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: AyudaFab(perfil: _perfil),
      body: SafeArea(
        // (4-oct-2026) El encabezado se compacta al desplazarse (no tapa el
        // contenido) y el buscador queda fijo debajo, siempre visible.
        child: CustomScrollView(
          slivers: [
            SliverPersistentHeader(
              pinned: true,
              delegate: _EncabezadoMenu(
                fecha: _fechaHoyTexto(),
                perfil: _perfil,
                escala: MediaQuery.textScalerOf(context).scale(1.0),
                onInfo: _abrirAcercaDe,
                onCambiar: () => _cambiarPerfil(context),
              ),
            ),
            SliverPersistentHeader(
              pinned: true,
              // La altura crece con el tamaño de letra que elija el alumno (A, A+, A++).
              delegate: _BuscadorFijo(alto: 62 + 56 * MediaQuery.textScalerOf(context).scale(1.0), construir: _buscadorPrincipal),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              sliver: SliverList(
                delegate: SliverChildListDelegate(
                [
                  _tarjetaHoy(),
                  _chipFinanzas(),
                  _tarjetaNotificaciones(),
                  // (4-oct-2026) El buscador ya no va aquí: quedó fijo arriba (_buscadorPrincipal).
                  if (_q.trim().isEmpty) ...[
                  if (_avisos.isNotEmpty) ...[
                    AvisosBanner(avisos: _avisos),
                    const SizedBox(height: 12),
                  ],
                  // (25-sep) Buzón de sugerencias, siempre a la vista.
                  _tarjetaSugerencia(),
                  const SizedBox(height: 12),
                  // (27-sep) Art. 48 y Arts. 49-58, Acuerdo 17/11/17.
                  if (_perfil != null && _perfil!.matricula.isNotEmpty) ...[
                    _tarjetaPendiente(
                      icon: Icons.report_gmailerrorred,
                      color: cessumGold,
                      texto: 'Presentar una queja',
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => QuejaScreen(matricula: _perfil!.matricula))),
                    ),
                    const SizedBox(height: 12),
                    _tarjetaPendiente(
                      icon: Icons.volunteer_activism_outlined,
                      color: cessumGold,
                      texto: 'Becas por convocatoria',
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => BecaConvocatoriaAlumnoScreen(matricula: _perfil!.matricula))),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_evalPendientes > 0) ...[
                    Material(
                      color: cessumRed.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () async {
                          final p = _perfil;
                          if (p == null) return;
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  EvaluacionDocenteScreen(perfil: p),
                            ),
                          );
                          _cargarEvalPendientes();
                        },
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: cessumRed.withValues(alpha: 0.5)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.rate_review,
                                  color: cessumRed, size: 26),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _evalPendientes == 1
                                      ? 'Evaluación docente pendiente (obligatoria)'
                                      : '$_evalPendientes evaluaciones docentes pendientes (obligatorias)',
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                    color: cessumRed,
                                  ),
                                ),
                              ),
                              const Icon(Icons.chevron_right,
                                  color: cessumRed),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_pendTramites > 0) ...[
                    _tarjetaPendiente(
                      icon: Icons.fact_check,
                      color: cessumGold,
                      texto: _pendTramites == 1
                          ? 'Tienes 1 trámite en proceso'
                          : 'Tienes $_pendTramites trámites en proceso',
                      onTap: () {
                        final p = _perfil;
                        if (p == null || p.matricula.isEmpty) return;
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                MisTramitesScreen(matricula: p.matricula),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_pendTitulacion.isNotEmpty &&
                      _pendTitulacion != 'Titulado') ...[
                    // (30-sep) Antes era solo informativa (no se podía tocar)
                    // y siempre dorada, aunque el turno fuera del alumno.
                    // Ahora lleva directo a Mi titulación, y se pone roja
                    // cuando de verdad requiere su acción.
                    _tarjetaPendiente(
                      icon: Icons.workspace_premium,
                      color: _pendTitulacionQuien == 'tu'
                          ? cessumRed
                          : cessumGold,
                      texto: 'Titulación: $_pendTitulacion',
                      onTap: () {
                        final p = _perfil;
                        if (p == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content:
                                  Text('Completa tu perfil para ver tu titulación'),
                            ),
                          );
                          return;
                        }
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const MiTitulacionScreen(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                  ],

                  if (_esAdmin) ...[
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: cessumRed,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        icon: const Icon(Icons.workspace_premium),
                        label: const Text(
                            'Identidad CESSUM · subir logos y manual'),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const IdentidadScreen(admin: true),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: cessumGold,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        icon: const Icon(Icons.school),
                        label: const Text('Becados · convenios de beca'),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const BecasAdminScreen(),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: cessumGold,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        icon: const Icon(Icons.insights),
                        label: const Text('Resultados de encuestas'),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const EncuestaResultadosScreen(),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Material(
                      color: cessumGold.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const TableroPendientesScreen(),
                          ),
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: cessumGold.withValues(alpha: 0.5)),
                          ),
                          child: Row(
                            children: const [
                              Icon(Icons.dashboard_customize,
                                  color: cessumGold, size: 26),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Tablero de pendientes',
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: cessumGold),
                                ),
                              ),
                              Icon(Icons.chevron_right, color: cessumGold),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Material(
                      color: cessumRed.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AdminHerramientasScreen(),
                          ),
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: cessumRed.withValues(alpha: 0.4)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.admin_panel_settings,
                                  color: cessumRed, size: 26),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  'Herramientas de administración',
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: cessumRed),
                                ),
                              ),
                              const Icon(Icons.chevron_right, color: cessumRed),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // (22-sep) TABLEROS DE DIRECCIÓN, A LA VISTA. Estaban solo
                    // en el catálogo del buscador: para llegar había que saber
                    // que existían y escribirlos. Aquí, como tarjetas.
                    _tablerosDireccion(),
                    const SizedBox(height: 8),
                    Material(
                      color: cessumGold.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const VerComoProfesorScreen(),
                          ),
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: cessumGold.withValues(alpha: 0.4)),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.cast_for_education,
                                  color: cessumGold, size: 26),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Ver como un profesor',
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: cessumGold),
                                ),
                              ),
                              Icon(Icons.chevron_right, color: cessumGold),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Material(
                      color: cessumGold.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AvanceCapturaScreen(),
                          ),
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: cessumGold.withValues(alpha: 0.4)),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.donut_large,
                                  color: cessumGold, size: 26),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text('Avance de captura',
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: cessumGold)),
                              ),
                              Icon(Icons.chevron_right, color: cessumGold),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Material(
                      color: cessumRed.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SaludDatosScreen(),
                          ),
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: cessumRed.withValues(alpha: 0.4)),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.fact_check, color: cessumRed, size: 26),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text('Salud de datos',
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: cessumRed)),
                              ),
                              Icon(Icons.chevron_right, color: cessumRed),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Material(
                      color: cessumGold.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const FirmasDocentesScreen(),
                          ),
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: cessumGold.withValues(alpha: 0.4)),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.draw, color: cessumGold, size: 26),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text('Firmas de docentes',
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: cessumGold)),
                              ),
                              Icon(Icons.chevron_right, color: cessumGold),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Material(
                      color: cessumRed.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const BitacoraScreen(),
                          ),
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: cessumRed.withValues(alpha: 0.4)),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.history, color: cessumRed, size: 26),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text('Bitácora de auditoría',
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: cessumRed)),
                              ),
                              Icon(Icons.chevron_right, color: cessumRed),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Material(
                      color: cessumGold.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const RolesAdminScreen(),
                          ),
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: cessumGold.withValues(alpha: 0.4)),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.admin_panel_settings,
                                  color: cessumGold, size: 26),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text('Roles de administración',
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: cessumGold)),
                              ),
                              Icon(Icons.chevron_right, color: cessumGold),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Material(
                      color: cessumGold.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const RespaldosScreen(),
                          ),
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: cessumGold.withValues(alpha: 0.4)),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.backup, color: cessumGold, size: 26),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text('Respaldos',
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: cessumGold)),
                              ),
                              Icon(Icons.chevron_right, color: cessumGold),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Material(
                      color: cessumRed.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const GraficasAprobacionScreen(),
                          ),
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: cessumRed.withValues(alpha: 0.4)),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.bar_chart, color: cessumRed, size: 26),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text('Aprobación / reprobación',
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: cessumRed)),
                              ),
                              Icon(Icons.chevron_right, color: cessumRed),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Material(
                      color: cessumGold.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AccesosUsoScreen(),
                          ),
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: cessumGold.withValues(alpha: 0.4)),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.login, color: cessumGold, size: 26),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text('Accesos y uso',
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: cessumGold)),
                              ),
                              Icon(Icons.chevron_right, color: cessumGold),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Material(
                      color: cessumRed.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const DocumentosEmitidosScreen(),
                          ),
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: cessumRed.withValues(alpha: 0.4)),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.verified, color: cessumRed, size: 26),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text('Documentos emitidos',
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: cessumRed)),
                              ),
                              Icon(Icons.chevron_right, color: cessumRed),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Material(
                      color: const Color(0xFF1E8E3E).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _abrirUrl('diagnostico'),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: const Color(0xFF1E8E3E).withValues(alpha: 0.4)),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.health_and_safety,
                                  color: Color(0xFF1E8E3E), size: 26),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Diagnóstico del sistema',
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF1E8E3E)),
                                ),
                              ),
                              Icon(Icons.open_in_new,
                                  color: Color(0xFF1E8E3E), size: 18),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Acceso rápido: ¿Qué necesitas hoy?
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                    decoration: BoxDecoration(
                      color: cessumRed,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '¿Qué necesitas hoy?',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            _accesoRapido(
                                context, Icons.assessment, 'Calificaciones',
                                () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const MiProgresoScreen(),
                                      ),
                                    )),
                            _accesoRapido(context, Icons.badge, 'Credencial',
                                () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const MiCredencialScreen(),
                                      ),
                                    )),
                            _accesoRapido(
                                context, Icons.description, 'Trámites',
                                () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const SolicitudTramitesScreen(),
                                      ),
                                    )),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ============================================================
                  // MENÚ DEL ALUMNO REORGANIZADO (jul-2026)
                  // Arriba: lo más usado, siempre visible. Abajo: el resto en
                  // grupos colapsables (mismo patrón que la Vista de admin).
                  // Fusiones: "Calendario y clases"+"Calendario" → Calendario;
                  // "Solicitar documentos oficiales"+"Trámites escolares" →
                  // una sola tarjeta (abrían la misma pantalla).
                  // ============================================================

                  // Invitación a evaluar (persuasiva, no bloqueante)
                  _bannerEvaluacion(),

                  // (18-sep) EL CHAT CON EL DOCENTE, A LA VISTA.
                  // Estaba solo en _catalogoOpciones(), que alimenta el
                  // BUSCADOR: para llegar a él había que saber que existía y
                  // escribirlo. Es el mismo caso que «Solicitar director de
                  // tesis» en agosto.
                  // Y aquí pesa más: la institución declara el chat como el
                  // único canal para dudas, así que un alumno que no lo
                  // encuentra termina escribiendo por WhatsApp al primero que
                  // le conteste. Va arriba, antes que nada.
                  Row(
                    children: [
                      _MenuCard(
                        icon: Icons.forum_outlined,
                        label: 'Chat con mi docente',
                        color: cessumRed,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const MensajesScreen(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Fila destacada: Mis clases (ancho completo)
                  Row(
                    children: [
                      _MenuCard(
                        icon: Icons.video_camera_front,
                        label: 'Mis clases y links de mis sesiones',
                        color: cessumRed,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const MisClasesScreen(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Acceso destacado: Mi panel
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: cessumRed,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const MiPanelScreen()),
                      ),
                      icon: const Icon(Icons.dashboard),
                      label: const Text('Mi panel',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Accesos rápidos siempre visibles
                  Row(
                    children: [
                      _MenuCard(
                        icon: Icons.school,
                        label: 'Aula virtual\n(Moodle)',
                        color: cessumRed,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const MiAulaScreen(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      _MenuCard(
                        icon: Icons.receipt_long,
                        label: 'Pagos',
                        color: cessumGold,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const PagosHubScreen(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _MenuCard(
                        icon: Icons.auto_awesome,
                        label: 'Asistente\nCESSUM',
                        color: cessumGold,
                        onTap: () {
                          final p = _perfil;
                          if (p == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'Completa tu perfil para usar el asistente'),
                              ),
                            );
                            return;
                          }
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AsistenteAlumnoScreen(perfil: p),
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 12),
                      _MenuCard(
                        icon: Icons.checklist,
                        label: 'Mis\npendientes',
                        color: cessumRed,
                        onTap: () async {
                          final p = _perfil;
                          if (p == null || p.matricula.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'Completa tu perfil para ver tus pendientes'),
                              ),
                            );
                            return;
                          }
                          final correo =
                              (await SessionStore.validEmail()) ?? '';
                          if (!mounted) return;
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => MisPendientesScreen(
                                matricula: p.matricula,
                                nombre: p.nombreCompleto,
                                correo: correo,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // (ago-7) Fila: Becas + Grabaciones de clase. Estaban solo
                  // en el catálogo del BUSCADOR (invisibles sin buscar) —
                  // aquí ganan su mosaico en la parrilla principal.
                  Row(
                    children: [
                      _MenuCard(
                        icon: Icons.workspace_premium,
                        label: 'Becas',
                        color: cessumGold,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const BecasScreen(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      _MenuCard(
                        icon: Icons.ondemand_video,
                        label: 'Grabaciones\nde clase',
                        color: cessumRed,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const GrabacionesClaseScreen(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Evaluación de materias y docentes (visible: es obligatoria)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: cessumGold,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      icon: const Icon(Icons.rate_review),
                      label: const Text('Evaluación de materias y docentes'),
                      onPressed: () {
                        final p = _perfil;
                        if (p == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                  'Completa tu perfil para responder la encuesta'),
                            ),
                          );
                          return;
                        }
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const EncuestaScreen(),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),

                  // (10-sep) MESA DE AYUDA, ARRIBA DE TODO.
                  // Estaba dentro del grupo «Comunidad y ayuda», al final de
                  // la pantalla: quien tiene un problema —un pago que no le
                  // aparece, una calificación que falta— tenía que recorrer
                  // seis grupos para encontrar dónde reportarlo, y muchos
                  // terminaban escribiendo por WhatsApp a quien tuvieran a
                  // mano. Aquí es lo primero que ve. Sigue estando también en
                  // su grupo, para quien ya lo busca donde siempre estuvo.
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: cessumRed.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: cessumRed.withValues(alpha: 0.28)),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () {
                          final p = _perfil;
                          if (p == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'Completa tu perfil para usar la Mesa de ayuda'),
                              ),
                            );
                            return;
                          }
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => MesaAyudaScreen(perfil: p),
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: cessumRed.withValues(alpha: 0.13),
                                  borderRadius: BorderRadius.circular(11),
                                ),
                                child: Icon(Icons.support_agent,
                                    color: cessumRed, size: 24),
                              ),
                              const SizedBox(width: 13),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '¿Tienes un problema? Mesa de ayuda',
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      'Un pago que no aparece, una calificación, '
                                      'un acceso: repórtalo aquí y queda con folio '
                                      'y seguimiento.',
                                      style: TextStyle(
                                        fontSize: 12,
                                        height: 1.35,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              Icon(Icons.chevron_right, color: cessumRed),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  // ===== GRUPO: Clases y horario =====
                  // (4-oct-2026) Los grupos, en cuadrícula de carpetas (ver _rejillaGrupos).
                  _rejillaGrupos([
                  _grupoMenu(
                    'Clases y horario',
                    'Horario, calendario, tareas, avisos y tutorías',
                    Icons.schedule,
                    [
                      Row(
                        children: [
                          _MenuCard(
                            icon: Icons.menu_book,
                            label: 'Mis\nmaterias',
                            color: cessumRed,
                            onTap: () async {
                              final p = _perfil;
                              if (p == null || p.matricula.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'Completa tu perfil para ver tus materias'),
                                  ),
                                );
                                return;
                              }
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => MateriasAlumnoScreen(
                                      matricula: p.matricula),
                                ),
                              );
                            },
                          ),
                          _MenuCard(
                            icon: Icons.history_edu,
                            label: 'Convenios',
                            color: cessumRed,
                            onTap: () async {
                              final p = _perfil;
                              if (p == null || p.matricula.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'Completa tu perfil para ver tus convenios'),
                                  ),
                                );
                                return;
                              }
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ConveniosAlumnoScreen(
                                      matricula: p.matricula),
                                ),
                              );
                            },
                          ),
                          _MenuCard(
                            icon: Icons.calendar_month,
                            label: 'Mi\nhorario',
                            color: cessumRed,
                            onTap: () async {
                              final p = _perfil;
                              if (p == null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'Completa tu perfil para ver tu horario'),
                                  ),
                                );
                                return;
                              }
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => MiHorarioScreen(perfil: p),
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 12),
                          _MenuCard(
                            icon: Icons.event,
                            label: 'Calendario',
                            color: cessumGold,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const CalendarioScreen(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _MenuCard(
                            icon: Icons.assignment_turned_in,
                            label: 'Tareas y\nentregas',
                            color: cessumRed,
                            onTap: () async {
                              final p = _perfil;
                              if (p == null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'Completa tu perfil para ver tus tareas'),
                                  ),
                                );
                                return;
                              }
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => TareasAlumnoScreen(perfil: p),
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 12),
                          _MenuCard(
                            icon: Icons.folder_shared,
                            label: 'Recursos y\nmateriales',
                            color: cessumGold,
                            onTap: () async {
                              final p = _perfil;
                              if (p == null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'Completa tu perfil para ver tus recursos'),
                                  ),
                                );
                                return;
                              }
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      RecursosAlumnoScreen(perfil: p),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _MenuCard(
                            icon: Icons.campaign,
                            label: 'Avisos de\nmaestros',
                            color: cessumGold,
                            onTap: () async {
                              final p = _perfil;
                              if (p == null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'Completa tu perfil para ver tus avisos'),
                                  ),
                                );
                                return;
                              }
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => AvisosAlumnoScreen(perfil: p),
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 12),
                          _MenuCard(
                            icon: Icons.notifications_active,
                            label: 'Mis\nrecordatorios',
                            color: cessumGold,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => RecordatoriosScreen(
                                    matricula: _perfil?.matricula ?? ''),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _MenuCard(
                            icon: Icons.support_agent,
                            label: 'Tutorías y\nasesorías',
                            color: cessumGold,
                            onTap: () {
                              final p = _perfil;
                              if (p == null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'Completa tu perfil para ver tus tutorías'),
                                  ),
                                );
                                return;
                              }
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      TutoriasAlumnoScreen(perfil: p),
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 12),
                          _MenuCard(
                            icon: Icons.menu_book,
                            label: 'Plan de\nestudios',
                            color: cessumGold,
                            onTap: () {
                              final prog = _perfil?.programa;
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => CartasDescriptivasScreen(
                                    programaFijo: (prog == null || prog.isEmpty)
                                        ? null
                                        : prog,
                                  ),
                                ),
                              );
                            },
                          ),

                        ],
                      ),
                    ],
                  ),

                  // ===== GRUPO: Mi avance académico =====
                  _grupoMenu(
                    'Mi avance académico',
                    'Calificaciones, boleta, plan de estudios y progreso',
                    Icons.insights,
                    [
                      Row(
                        children: [
                          _MenuCard(
                            icon: Icons.assessment,
                            label: 'Mi progreso\nacadémico',
                            color: cessumRed,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const MiProgresoScreen(),
                              ),
                            ),
                          ),
                          // (8-sep) El concentrado, a la vista de quien lo usa.
                          // Estaba dos niveles adentro y el buscador no lo
                          // hallaba. Solo se muestra a administración: para un
                          // alumno no tendría sentido ver el grupo completo.
                          if (_esAdmin) const SizedBox(width: 12),
                          if (_esAdmin)
                            _MenuCard(
                              icon: Icons.grid_on,
                              label: 'Concentrado\npor grupo',
                              color: cessumGold,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const MatrizGrupoScreen()),
                              ),
                            ),

                          const SizedBox(width: 12),
                          _MenuCard(
                            icon: Icons.calculate,
                            label: 'Calculadora\nde promedio',
                            color: cessumGold,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    const CalculadoraPromedioScreen(),
                              ),
                            ),
                          ),

                          

                          
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _MenuCard(
                            icon: Icons.psychology,
                            label: 'Mi perfil\nde aprendizaje',
                            color: cessumRed,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PerfilAprendizajeScreen(
                                  matricula: _perfil?.matricula ?? '',
                                  nombre: _perfil?.nombreCompleto ?? '',
                                  programa: _perfil?.programa ?? '',
                                  generacion: _perfil?.generacion ?? '',
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          _MenuCard(
                            icon: Icons.groups,
                            label: 'Aprendizaje\nde mis grupos',
                            color: cessumGold,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const DocenteModosScreen(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _MenuCard(
                            icon: Icons.replay_circle_filled,
                            label: 'Recursamientos',
                            color: cessumGold,
                            onTap: () async {
                              final p = _perfil;
                              if (p == null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'Completa tu perfil para ver tus recursamientos'),
                                  ),
                                );
                                return;
                              }
                              final correo =
                                  await SessionStore.validEmail() ?? '';
                              if (!mounted) return;
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => RecursamientosScreen(
                                    matricula: p.matricula,
                                    correo: correo,
                                    nombre: p.nombreCompleto,
                                    programa: p.programa,
                                    generacion: p.generacion,
                                  ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 12),
                          // (25-sep) Mi ruta al título: el camino completo con coach con IA.
                          _MenuCard(
                            icon: Icons.route,
                            label: 'Mi ruta\nal título',
                            color: cessumRed,
                            onTap: () {
                              if (_perfil == null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Completa tu perfil para ver tu ruta')),
                                );
                                return;
                              }
                              Navigator.push(context, MaterialPageRoute(builder: (_) => const MiRutaScreen()));
                            },
                          ),
                        ],
                      ),
                    ],
                  ),

                  // ===== GRUPO: Trámites y solicitudes =====
                  _grupoMenu(
                    'Trámites y solicitudes',
                    'Documentos oficiales, reinscripción, factura, baja y más',
                    Icons.description,
                    [
                      Row(
                        children: [
                          _MenuCard(
                            icon: Icons.description,
                            label: 'Solicitar un\ndocumento',
                            color: cessumGold,
                            onTap: () {
                              final p = _perfil;
                              if (p == null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'Completa tu perfil para generar documentos'),
                                  ),
                                );
                                return;
                              }
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const SolicitudTramitesScreen(),
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 12),
                          _MenuCard(
                            icon: Icons.receipt_long,
                            label: 'Mi\nboleta',
                            color: cessumGold,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    MiBoletaScreen(perfil: _perfil),
                              ),
                            ),
                          ),

                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _MenuCard(
                            icon: Icons.fact_check,
                            label: 'Mis\ntrámites',
                            color: cessumRed,
                            onTap: () {
                              final p = _perfil;
                              if (p == null || p.matricula.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'Completa tu perfil para ver tus trámites'),
                                  ),
                                );
                                return;
                              }
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => MisTramitesScreen(
                                      matricula: p.matricula),
                                ),
                              );
                            },
                          ),
                          
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _MenuCard(
                            icon: Icons.refresh,
                            label: 'Reinscripción',
                            color: cessumGold,
                            onTap: () => Helpers.abrirUrlExterna(
                              formReinscripcionUrl,
                              context,
                            ),
                          ),
                          const SizedBox(width: 12),
                          _MenuCard(
                            icon: Icons.receipt_long,
                            label: 'Solicitud\nde factura',
                            color: cessumRed,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    const SolicitudFacturaScreen(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _MenuCard(
                            icon: Icons.event_busy,
                            label: 'Justificación\nde faltas',
                            color: cessumGold,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    const JustificacionFaltasScreen(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          _MenuCard(
                            icon: Icons.sync_alt,
                            label: 'Adaptación\nde modalidad',
                            color: cessumGold,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    const SolicitudAdaptacionModalidadScreen(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _MenuCard(
                            icon: Icons.swap_horiz,
                            label: 'Cambio de\nprograma',
                            color: cessumGold,
                            onTap: () {
                              final p = _perfil;
                              if (p == null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'Completa tu perfil para solicitar el cambio'),
                                  ),
                                );
                                return;
                              }
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const SolicitudCambioProgramaScreen(),
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 12),
                          _MenuCard(
                            icon: Icons.exit_to_app,
                            label: 'Solicitar\nbaja',
                            color: cessumRed,
                            onTap: () {
                              final p = _perfil;
                              if (p == null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'Completa tu perfil para solicitar la baja'),
                                  ),
                                );
                                return;
                              }
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const SolicitudBajaScreen(),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),

                  // ===== GRUPO: Titulación y tesis =====
                  _grupoMenu(
                    'Titulación y tesis',
                    'Tu proceso de titulación, expediente y tesis',
                    Icons.workspace_premium,
                    [
                      Row(
                        children: [
                          _MenuCard(
                            icon: Icons.timeline,
                            label: 'Mi titulación\npaso a paso',
                            color: cessumGold,
                            onTap: () {
                              final p = _perfil;
                              if (p == null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'Completa tu perfil para ver tu titulación'),
                                  ),
                                );
                                return;
                              }
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const MiTitulacionScreen(),
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 12),
                          // (14-sep) MI EXPEDIENTE DE TITULACIÓN vuelve al grupo.
                          // Se había quitado el 8-sep porque lo que se subía ahí
                          // después de solicitar no llegaba a revisión; el
                          // Guardián ya escribe en las dos hojas, así que la
                          // pantalla sirve en cualquier momento. Va junto a
                          // «Mi titulación» porque son las dos puertas del
                          // mismo proceso: una para el trámite, otra para los
                          // documentos.
                          _MenuCard(
                            icon: Icons.folder_copy,
                            label: 'Mi expediente\nde titulación',
                            color: cessumRed,
                            onTap: () {
                              final p = _perfil;
                              if (p == null || p.matricula.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'Completa tu perfil para ver tu expediente'),
                                  ),
                                );
                                return;
                              }
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      MiExpedienteTitulacionScreen(perfil: p),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          // (ago-22) SOLICITAR DIRECTOR DE TESIS.
                          // La pantalla existía desde agosto y funcionaba, pero
                          // solo se llegaba a ella escribiendo "tutor" en el
                          // buscador: vivía únicamente en _catalogoOpciones(),
                          // que solo alimenta los resultados de búsqueda. Un
                          // alumno que entraba a "Titulación y tesis" veía el
                          // paso siguiente —Mi tesis— pero no el primero.
                          // Va antes de "Mi tesis" porque ése es el orden real:
                          // sin director asignado no hay convenio que llenar.
                          _MenuCard(
                            icon: Icons.person_search,
                            label: 'Solicitar\ndirector de tesis',
                            color: cessumRed,
                            onTap: () {
                              final p = _perfil;
                              if (p == null || p.matricula.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'Completa tu perfil para solicitar director de tesis'),
                                  ),
                                );
                                return;
                              }
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => SolicitarTutorScreen(
                                      matricula: p.matricula),
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 12),
                          _MenuCard(
                            icon: Icons.school,
                            label: 'Mi tesis (convenio y avances)',
                            color: cessumGold,
                            onTap: () async {
                              final p = _perfil;
                              if (p == null || p.matricula.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'Completa tu perfil para ver tu tesis'),
                                  ),
                                );
                                return;
                              }
                              final correo =
                                  (await SessionStore.validEmail()) ?? '';
                              if (!mounted) return;
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => TesisConvenioScreen(
                                    matricula: p.matricula,
                                    nombre: p.nombreCompleto,
                                    correo: correo,
                                    rol: 'alumno',
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),

                  // ===== GRUPO: Comunidad y ayuda =====
                  _grupoMenu(
                    'Comunidad y ayuda',
                    'Mesa de ayuda, buzones, eventos y más',
                    Icons.diversity_3,
                    [
                      Row(
                        children: [
                          _MenuCard(
                            icon: Icons.support_agent,
                            label: 'Mesa de\nayuda',
                            color: cessumRed,
                            onTap: () {
                              final p = _perfil;
                              if (p == null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'Completa tu perfil para usar la Mesa de ayuda'),
                                  ),
                                );
                                return;
                              }
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => MesaAyudaScreen(perfil: p),
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 12),
                          _MenuCard(
                            icon: Icons.event_available,
                            label: 'Eventos',
                            color: cessumRed,
                            onTap: () async {
                              final p = _perfil;
                              if (p == null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'Completa tu perfil para ver tus eventos'),
                                  ),
                                );
                                return;
                              }
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => EventosScreen(perfil: p),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          
                          
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _MenuCard(
                            icon: Icons.campaign,
                            label: 'Convocatorias\nvigentes',
                            color: cessumRed,
                            onTap: () => Helpers.abrirUrlExterna(
                              convocatoriasUrl,
                              context,
                            ),
                          ),
                          const SizedBox(width: 12),
                          _MenuCard(
                            icon: Icons.feedback,
                            label: 'Buzón',
                            color: cessumRed,
                            onTap: () {
                              final p = _perfil;
                              if (p == null || p.matricula.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'Completa tu perfil para usar el buzón'),
                                  ),
                                );
                                return;
                              }
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => BuzonScreen(
                                    matricula: p.matricula,
                                    nombre: p.nombreCompleto,
                                  ),
                                ),
                              );
                            },
                          ),

                          const SizedBox(width: 12),
                          // (8-sep) UN SOLO PROGRAMA DE REFERIDOS.
                          // Convivían dos: esta tarjeta abría «Recomienda y
                          // gana» y el buscador llevaba a «Invita a alguien».
                          // No eran dos vistas de lo mismo: generaban CÓDIGOS
                          // DISTINTOS —uno desde la matrícula, otro desde el
                          // correo— y los guardaban en hojas separadas. El
                          // alumno compartía el código de la pantalla por la
                          // que hubiera entrado y administración lo buscaba en
                          // la otra hoja, así que la bonificación no se pagaba
                          // y quedaba mal con la persona que recomendó.
                          // Queda «Invita a alguien», que liga al referido solo
                          // con el enlace y no depende de un cruce manual.
                          _MenuCard(
                            icon: Icons.volunteer_activism_outlined,
                            label: 'Invita\na alguien',
                            color: cessumRed,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const ReferidosScreen()),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _MenuCard(
                            icon: Icons.sports_esports,
                            label: 'Juegos',
                            color: cessumRed,
                            onTap: () {
                              final p = _perfil;
                              if (p == null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content:
                                        Text('Completa tu perfil para jugar'),
                                  ),
                                );
                                return;
                              }
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => JuegosHubScreen(perfil: p),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),

                  // ===== GRUPO: Mi identidad =====
                  _grupoMenu(
                    'Mi identidad',
                    'Perfil, credencial y firma',
                    Icons.badge,
                    [
                      Row(
                        children: [
                          _MenuCard(
                            icon: Icons.manage_accounts,
                            label: 'Mi\nperfil',
                            color: cessumGold,
                            onTap: _abrirMiPerfil,
                          ),
                          const SizedBox(width: 12),
                          _MenuCard(
                            icon: Icons.badge,
                            label: 'Mi\ncredencial',
                            color: cessumRed,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const MiCredencialScreen(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _MenuCard(
                            icon: Icons.draw,
                            label: 'Mi\nfirma',
                            color: cessumRed,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => FirmaAlumnoScreen(
                                    matricula: _perfil?.matricula ?? ''),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  // ===== GRUPO: CESSUM e información =====
                  _grupoMenu(
                    'CESSUM e información',
                    'Guía, contacto, identidad, formatos y APA',
                    Icons.info_outline,
                    [
                      Row(
                        children: [
                          _MenuCard(
                            icon: Icons.help_outline,
                            label: 'Guía de\nbienvenida',
                            color: cessumRed,
                            onTap: () =>
                                mostrarOnboardingAhora(context, _perfil),
                          ),
                          const SizedBox(width: 12),
                          _MenuCard(
                            icon: Icons.info_outline,
                            label: 'Acerca de\nCESSUM',
                            color: cessumGold,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const AcercaScreen(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _MenuCard(
                            icon: Icons.contact_support,
                            label: 'Contacto y\ndatos útiles',
                            color: cessumGold,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ContactoScreen(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          _MenuCard(
                            icon: Icons.workspace_premium,
                            label: 'Identidad\nCESSUM',
                            color: cessumGold,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    IdentidadScreen(admin: _esAdmin),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _MenuCard(
                            icon: Icons.folder_copy,
                            label: 'Banco de\nformatos',
                            color: cessumRed,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    FormatosScreen(admin: _esAdmin),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          _MenuCard(
                            icon: Icons.menu_book,
                            label: 'Referencias\nAPA 7',
                            color: cessumRed,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    const ApaReferenciasScreen(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  ]),

                  const SizedBox(height: 4),

                  // Boton WhatsApp ancho
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF25D366),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                      onPressed: () => Helpers.abrirWhatsApp(context),
                      icon: const Icon(Icons.chat, size: 22),
                      label: const Text(
                        'WhatsApp - Atencion a alumnos',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Boton Llamar ancho
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: cessumRed,
                        side: const BorderSide(color: cessumRed, width: 1.5),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () => Helpers.llamarPorTelefono(
                        context,
                        telefonoAdmisiones,
                      ),
                      icon: const Icon(Icons.phone, size: 22),
                      label: Text(
                        'Llamar - $telefonoAdmisionesFormateado',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Boton Gmail
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFD93025),
                        side: const BorderSide(
                          color: Color(0xFFD93025),
                          width: 1.5,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () => Helpers.abrirGmail(context),
                      icon: const Icon(Icons.email, size: 22),
                      label: const Text(
                        'Abrir Gmail',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  ValueListenableBuilder<ThemeMode>(
                    valueListenable: themeNotifier,
                    builder: (context, modo, _) => SwitchListTile(
                      value: modo == ThemeMode.dark,
                      onChanged: (v) =>
                          guardarTema(v ? ThemeMode.dark : ThemeMode.light),
                      activeColor: cessumGold,
                      secondary: Icon(
                        modo == ThemeMode.dark
                            ? Icons.dark_mode
                            : Icons.light_mode,
                        color: cessumGold,
                      ),
                      title: const Text('Modo oscuro',
                          style: TextStyle(fontSize: 13.5)),
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                    child: Row(
                      children: [
                        const Icon(Icons.format_size,
                            color: cessumGold, size: 22),
                        const SizedBox(width: 12),
                        const Text('Tamaño de letra',
                            style: TextStyle(fontSize: 13.5)),
                        const Spacer(),
                        ValueListenableBuilder<double>(
                          valueListenable: textScaleNotifier,
                          builder: (context, escala, _) =>
                              SegmentedButton<double>(
                            showSelectedIcon: false,
                            style: const ButtonStyle(
                                visualDensity: VisualDensity.compact),
                            segments: const [
                              ButtonSegment(
                                  value: 1.0,
                                  label: Text('A',
                                      style: TextStyle(fontSize: 13))),
                              ButtonSegment(
                                  value: 1.2,
                                  label: Text('A',
                                      style: TextStyle(fontSize: 16))),
                              ButtonSegment(
                                  value: 1.4,
                                  label: Text('A',
                                      style: TextStyle(fontSize: 19))),
                            ],
                            selected: {
                              escala >= 1.3
                                  ? 1.4
                                  : (escala >= 1.1 ? 1.2 : 1.0)
                            },
                            onSelectionChanged: (s) =>
                                guardarTextScale(s.first),
                          ),
                        ),
                      ],
                    ),
                  ),

                  ] else ...[
                    ..._resultadosBusqueda(),
                  ],

                  const EstadoConexion(),

                  // Pie con version y enlace al aviso de privacidad
                  Center(
                    child: Column(
                      children: [
                        Text(
                          '$_version - App CESSUM',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.black45,
                          ),
                        ),
                        const SizedBox(height: 4),
                        InkWell(
                          onTap: () => Helpers.abrirUrlExterna(
                            avisoPrivacidadUrl,
                            context,
                          ),
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Text(
                              'Aviso de privacidad',
                              style: TextStyle(
                                fontSize: 11,
                                color: cessumRed,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SaludoPerfil extends StatelessWidget {
  final StudentProfile perfil;

  const _SaludoPerfil({required this.perfil});

  @override
  Widget build(BuildContext context) {
    final nombreVisible = perfil.nombreCompleto.isNotEmpty
        ? perfil.nombreCompleto
        : 'Matricula ${perfil.matricula}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: cessumRed.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.person, color: cessumRed, size: 18),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  nombreVisible,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${perfil.generacion} - ${perfil.modalidad}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.black54,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _MenuCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        elevation: 1,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(16),
            height: 120,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 28),
                ),
                const SizedBox(height: 10),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


Widget _accesoRapido(
    BuildContext context, IconData icon, String label, VoidCallback onTap) {
  return Expanded(
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 24),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}


// Una opción del menú para el buscador: nombre, descripción (también se
// busca por ella), icono y la acción que abre.
/// Una opción del menú del alumno.
///
/// (ago-25) `soloAdmin` existe porque el catálogo alimenta el BUSCADOR, y el
/// buscador no filtraba nada: cualquier alumno que escribiera «grupos» o
/// «recursamiento» llegaba a pantallas de docente o de Vicerrectoría. Ahí no
/// encontraba un permiso denegado —eso sería honesto— sino un mensaje que le
/// hacía creer que algo andaba mal con su inscripción.
///
/// El filtro es por omisión INCLUSIVO: una opción sin marcar es del alumno.
/// Así, quien agregue una opción nueva sin pensar en esto no rompe nada; solo
/// hay que marcar las que NO son suyas.
class _OpcionMenu {
  final String nombre;
  final String descripcion;
  final IconData icono;
  final VoidCallback accion;

  /// Solo para administradores (Vicerrectoría, Rectoría, coordinaciones).
  final bool soloAdmin;

  const _OpcionMenu(this.nombre, this.descripcion, this.icono, this.accion,
      {this.soloAdmin = false});
}

/// (4-oct-2026) Un grupo del menú como «carpeta»: título, una línea de
/// descripción, ícono y sus filas de tarjetas (las mismas de siempre).
class _Carpeta {
  final String titulo;
  final String subtitulo;
  final IconData icono;
  final List<Widget> hijos;
  const _Carpeta(this.titulo, this.subtitulo, this.icono, this.hijos);
}

/// (4-oct-2026) Encabezado que se COMPACTA al desplazarse: arriba, el venado,
/// «App CESSUM», la fecha y el alumno; al bajar, queda una barra delgada con
/// el logotipo pequeño y el nombre, para no tapar el contenido.
class _EncabezadoMenu extends SliverPersistentHeaderDelegate {
  final String fecha;
  final StudentProfile? perfil;
  final VoidCallback onInfo;
  final VoidCallback onCambiar;
  final double escala;   // tamaño de letra elegido: el encabezado crece con él
  _EncabezadoMenu({required this.fecha, required this.perfil, required this.onInfo, required this.onCambiar, this.escala = 1.0});

  @override
  double get maxExtent => (perfil != null ? 214 : 164) + 60 * (escala - 1).clamp(0.0, 1.0);
  @override
  double get minExtent => 58;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final t = (shrinkOffset / (maxExtent - minExtent)).clamp(0.0, 1.0);
    final nombre = perfil == null
        ? ''
        : (perfil!.nombreCompleto.isNotEmpty ? perfil!.nombreCompleto : 'Matrícula ${perfil!.matricula}');
    return Material(
      color: Colors.white,
      elevation: t > 0.95 ? 2 : 0,
      child: ClipRect(
        child: Stack(children: [
          // Lo grande: se desvanece y sube al desplazarse.
          Positioned(
            left: 0,
            right: 0,
            top: 6 - shrinkOffset * 0.35,
            child: Opacity(
              opacity: (1 - t * 1.6).clamp(0.0, 1.0),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Image.asset('assets/images/logo.png', height: 56, fit: BoxFit.contain),
                const SizedBox(height: 6),
                const Text('App CESSUM',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.black87)),
                const SizedBox(height: 2),
                Text(fecha, style: const TextStyle(fontSize: 12.5, color: Colors.black54, fontWeight: FontWeight.w500)),
                if (perfil != null) ...[
                  const SizedBox(height: 10),
                  _SaludoPerfil(perfil: perfil!),
                ],
              ]),
            ),
          ),
          // La barra compacta: aparece al desplazarse.
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 58,
            child: Row(children: [
              IconButton(
                icon: const Icon(Icons.info_outline, color: cessumRed),
                tooltip: 'Acerca de',
                onPressed: onInfo,
              ),
              Expanded(
                child: Opacity(
                  opacity: ((t - 0.55) / 0.45).clamp(0.0, 1.0),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Image.asset('assets/images/logo.png', height: 28, fit: BoxFit.contain),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(nombre.isEmpty ? 'App CESSUM' : nombre,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.black87)),
                    ),
                  ]),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.swap_horiz, color: cessumRed),
                tooltip: 'Cambiar perfil',
                onPressed: onCambiar,
              ),
            ]),
          ),
          // Franja de marca al pie del encabezado.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 3,
            child: Opacity(
              opacity: t,
              child: Container(
                decoration: const BoxDecoration(gradient: LinearGradient(colors: [cessumRed, cessumGold])),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _EncabezadoMenu old) =>
      old.fecha != fecha || old.perfil != perfil || old.escala != escala;
}

/// (4-oct-2026) El buscador queda FIJO bajo el encabezado, siempre visible.
class _BuscadorFijo extends SliverPersistentHeaderDelegate {
  final double alto;
  final Widget Function() construir;
  _BuscadorFijo({required this.alto, required this.construir});

  @override
  double get maxExtent => alto;
  @override
  double get minExtent => alto;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) =>
      SizedBox(height: alto, child: construir());

  @override
  bool shouldRebuild(covariant _BuscadorFijo old) => true;
}

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';
import 'matriz_grupo_screen.dart';
import 'centro_salud_screen.dart';
import 'centro_datos_screen.dart';
import 'pulso_admin_screen.dart';
import 'ia_vigilancia_screen.dart';
import 'decision_academica_screen.dart';
import 'uso_app_screen.dart';
import 'becas_admin_screen.dart';
import 'coinedu_admin_screen.dart';
import 'calidad_plataforma_screen.dart';
import 'centro_calidad_screen.dart';
import 'siga_screen.dart';
import 'diag_calif_screen.dart';
import 'tablero_calendarizacion_screen.dart';
import 'boletas_pendientes_screen.dart';

/// Accesos directos a las herramientas de administración (paneles web que
/// sirve el backend). Cada opción abre la URL correspondiente del Guardián,
/// que inyecta la clave automáticamente.
///
/// (ago-7) Se agregó la sección "Datos y autoridad educativa". Motivo: el
/// barrido de alcanzabilidad encontró que centro_datos_screen.dart y
/// siga_screen.dart no los importaba NADIE, así que el Centro de datos y la
/// Cabina SIGA completa —construidos el 6-ago— eran inalcanzables desde la
/// app. Esta pantalla sí cuelga del menú, así que aquí queda su puerta.
class AdminHerramientasScreen extends StatefulWidget {
  const AdminHerramientasScreen({super.key});

  @override
  State<AdminHerramientasScreen> createState() => _AdminHerramientasScreenState();
}

/// (24-sep) Con estado para el BUSCADOR: son más de 30 herramientas.
/// Además, los paneles que pueden enviar correos a alumnos llevan su marca y
/// avisan antes de abrirse (dentro, el panel muestra a quiénes antes de enviar).
class _AdminHerramientasScreenState extends State<AdminHerramientasScreen> {
  final _q = TextEditingController();
  static const Set<String> _envianCorreos = {'recordatorios', 'felicitar_cumple'};

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  bool _coincide(String titulo, [String detalle = '']) {
    final q = _q.text.trim().toLowerCase();
    if (q.isEmpty) return true;
    return '$titulo $detalle'.toLowerCase().contains(q);
  }

  Future<void> _abrirConAviso(BuildContext context, String accion, String titulo) async {
    if (_envianCorreos.contains(accion)) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(titulo, style: const TextStyle(fontSize: 16)),
          content: const Text(
              'Este panel puede ENVIAR CORREOS a alumnos. Al abrirlo no se envía nada: '
              'dentro verá a quiénes les llegaría y qué, y usted decide si confirma.',
              style: TextStyle(fontSize: 13.5, height: 1.4)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Abrir panel'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    if (!context.mounted) return;
    await _abrir(context, accion);
  }

  Future<void> _abrir(BuildContext context, String accion) async {
    final uri = Uri.parse('$guardianUrl?accion=$accion');
    try {
      await launchUrl(uri,
          mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank');
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo abrir la herramienta.')),
        );
      }
    }
  }

  /// La Cabina SIGA necesita el correo del admin para auditar y firmar la
  /// bitácora, así que se resuelve la sesión antes de abrirla.
  Future<void> _abrirSiga(BuildContext context) async {
    // (24-sep) Correo REAL: en «Ver como profesor» validEmail() devuelve el del
    // profesor, y el Guardián rechazaría la acción por no ser administrador.
    final actor = (await SessionStore.realEmail()) ?? '';
    if (!context.mounted) return;
    if (actor.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Tu sesión expiró. Vuelve a entrar.')),
      );
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SigaScreen(actor: actor)),
    );
  }

  /// Tarjeta de pantalla nativa (no abre URL del navegador).
  Widget _tarjeta({
    required BuildContext context,
    required IconData icono,
    required String titulo,
    required String detalle,
    required VoidCallback onTap,
    bool destacada = false,
  }) {
    if (!_coincide(titulo, detalle)) return const SizedBox.shrink();
    final color = destacada ? cessumGold : cessumRed;
    return Card(
      margin: EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.12),
          child: Icon(icono, color: color),
        ),
        title:
            Text(titulo, style: TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(detalle, style: TextStyle(fontSize: 12)),
        trailing: Icon(Icons.chevron_right, size: 20),
        onTap: onTap,
      ),
    );
  }

  Widget _encabezado(String texto) => _q.text.trim().isNotEmpty
      ? const SizedBox.shrink()
      : Padding(
        padding: EdgeInsets.fromLTRB(4, 16, 4, 6),
        child: Text(
          texto,
          style: TextStyle(
              fontSize: 14, fontWeight: FontWeight.w800, color: cessumRed),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final secciones = <String, List<List<dynamic>>>{
      'Diagnóstico y verificación': [
        ['Diagnóstico del sistema', Icons.health_and_safety, 'diagnostico'],
        ['Prueba de extremo a extremo', Icons.fact_check, 'prueba_e2e'],
        ['Salud de datos', Icons.dataset, 'salud_datos'],
        ['Registro de errores', Icons.bug_report, 'errores_admin'],
        ['Verificar y alertar', Icons.notifications_active, 'verificar_alertar'],
      ],
      'Gestión': [
        ['Tablero de métricas', Icons.insights, 'metricas'],
        ['Reportes exportables', Icons.download, 'reporte'],
        ['Buscar alumno', Icons.person_search, 'buscar_alumno'],
        ['Solicitudes de credencial', Icons.badge, 'credenciales_admin'],
        ['Trámites en lote', Icons.checklist, 'tramites_lote'],
        ['Buzón de sugerencias', Icons.feedback, 'sugerencias_admin'],
        ['Bitácora de auditoría', Icons.history, 'bitacora'],
      ],
      'Mantenimiento': [
        ['Respaldo ahora', Icons.backup, 'respaldo_manual'],
        ['Limpiar duplicados', Icons.cleaning_services, 'limpiar_duplicados'],
        ['Normalizar generaciones', Icons.auto_fix_high, 'limpiar_generaciones'],
        ['Enviar recordatorios', Icons.mail, 'recordatorios'],
        ['Felicitar cumpleaños', Icons.cake, 'felicitar_cumple'],
      ],
    };

    final hijos = <Widget>[];

    // =================================================================
    //  DATOS Y AUTORIDAD EDUCATIVA  (puerta al Centro de datos y a SIGA)
    // =================================================================
    // (ago-9) El pulso va PRIMERO: es lo que contesta "¿hay algo que se me
    // esté pasando?" sin tener que abrir el correo ni pegar URLs.
    hijos.add(_encabezado('Pulso'));
    hijos.add(_tarjeta(
      context: context,
      icono: Icons.monitor_heart_outlined,
      titulo: 'Pulso institucional',
      detalle:
          'Qué espera decisión, desde cuándo, y si alguna automatización se '
          'cayó. Es lo mismo que llega por correo, cuando tú quieras.',
      destacada: true,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const PulsoAdminScreen()),
      ),
    ));
    // (24-sep) IA · Fase 4.
    hijos.add(_tarjeta(
      context: context,
      icono: Icons.radar,
      titulo: 'Vigilante de admisiones',
      detalle: 'Avisa cuando el embudo se rompe: panel sin prospectos, formularios en silencio, '
          'inscritos fuera del panel, gasto de Meta sin registrar. Los lunes, resumen con IA.',
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const VigilanteAdmisionesScreen()),
      ),
    ));
    hijos.add(_tarjeta(
      context: context,
      icono: Icons.summarize_outlined,
      titulo: 'Resúmenes de clase con IA',
      detalle: 'Temas, ideas y tareas de cada clase grabada en Meet, para quien faltó. '
          'Se revisan y se publican al grupo en la app.',
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ResumenesClaseScreen()),
      ),
    ));
    // (25-sep) Panel de decisión académica.
    // (25-sep) Uso real de la app y buzón de sugerencias de los alumnos.
    hijos.add(_tarjeta(
      context: context,
      icono: Icons.touch_app_outlined,
      titulo: 'Uso de la app y sugerencias',
      detalle: 'A qué pantallas entran los alumnos, qué accesos agrandar, cuáles van primero y cuáles reagrupar; '
          'buzón de sugerencias con respuesta al alumno.',
      destacada: true,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const UsoAppScreen()),
      ),
    ));
    hijos.add(_tarjeta(
      context: context,
      icono: Icons.insights,
      titulo: 'Decisión académica (evaluación docente)',
      detalle: 'De la evaluación de los alumnos a decisiones: dimensiones débiles, docentes por segmento, '
          'comentarios analizados con IA, planes de mejora y seguimiento del efecto.',
      destacada: true,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const DecisionAcademicaScreen()),
      ),
    ));

    // (ago-9) BECADOS NO ERA ENCONTRABLE. El buscador del panel indexa
    // TARJETAS, y "Becados · convenios de beca" vivía como un BOTÓN dentro de
    // otra tarjeta: no aparecía por más que se buscara "becas" o "crédito
    // educativo". Buscar "becas" llevaba a la pantalla del ALUMNO, que es
    // otra cosa. Aquí queda como tarjeta propia, con las palabras que
    // realmente se teclean al buscarla.
    hijos.add(_encabezado('Calidad'));
    // (2-sep) UN SOLO CENTRO DE CALIDAD. La opinión sobre la app, la de los
    // docentes y el buzón anónimo vivían en pantallas separadas que nadie
    // cruzaba: el número de la app no dice si el problema es la app o el
    // proceso, y el buzón no se leía junto a la evaluación que lo explica.
    hijos.add(_tarjeta(
      context: context,
      icono: Icons.insights_outlined,
      titulo: 'Centro de calidad',
      detalle:
          'Todo lo que dicen los alumnos en un solo lugar: plataforma, '
          'evaluación docente, procesos y buzón anónimo, con el tamaño de '
          'muestra a la vista y respuesta por respuesta.',
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const CentroCalidadScreen()),
      ),
    ));

    hijos.add(_encabezado('Congreso'));
    hijos.add(_tarjeta(
      context: context,
      icono: Icons.workspace_premium_outlined,
      titulo: 'COINEDU 2026 · dictaminar ponencias y carteles',
      detalle:
          'Contribuciones recibidas, dictamen por pares, notificación al '
          'autor, seguimiento de pago y extenso, y el calendario del congreso.',
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const CoineduAdminScreen()),
      ),
    ));

    hijos.add(_encabezado('Becas'));
    hijos.add(_tarjeta(
      context: context,
      icono: Icons.school,
      titulo: 'Becados · autorizar becas y crédito educativo',
      detalle:
          'Dictamina las solicitudes que suben los alumnos (IBCEES, crédito '
          'educativo, USICAMM, convenios), captura el porcentaje y genera el '
          'convenio de beca.',
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const BecasAdminScreen()),
      ),
    ));

    hijos.add(_encabezado('Datos y autoridad educativa'));
    hijos.add(_tarjeta(
      context: context,
      icono: Icons.account_balance,
      titulo: 'Cabina SIGA',
      detalle:
          'Los 5 exportables para la SEC: auditoría por ciclo, equivalencias, '
          'periodos faltantes y paquete completo en Drive.',
      destacada: true,
      onTap: () => _abrirSiga(context),
    ));
    hijos.add(_tarjeta(
      context: context,
      icono: Icons.storage,
      titulo: 'Centro de datos',
      detalle:
          'Mantenimiento en un solo lugar: actas, expediente del alumno, '
          'salud de datos y bajas. También abre SIGA desde su barra.',
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const CentroDatosScreen()),
      ),
    ));

    // Sección destacada: Concentrado de calificaciones por grupo (matriz editable).
    hijos.add(_encabezado('Calificaciones'));
    hijos.add(_tarjeta(
      context: context,
      icono: Icons.grid_on,
      titulo: 'Concentrado por grupo',
      detalle:
          'Matriz alumnos × materias. Edita calificaciones y detecta faltantes.',
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const MatrizGrupoScreen()),
      ),
    ));
    hijos.add(_tarjeta(
      context: context,
      icono: Icons.mark_email_unread,
      titulo: 'Notificar boletas pendientes',
      detalle:
          'Detecta calificaciones validadas sin boleta enviada y las manda.',
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const BoletasPendientesScreen()),
      ),
    ));

    // Sección: Salud y diagnóstico (pantallas nativas, no URLs).
    hijos.add(_encabezado('Salud y diagnóstico'));
    hijos.add(_tarjeta(
      context: context,
      icono: Icons.health_and_safety,
      titulo: 'Centro de Salud',
      detalle:
          'Radiografía de todas las bases y arreglos seguros en un solo lugar.',
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const CentroSaludScreen()),
      ),
    ));
    hijos.add(_tarjeta(
      context: context,
      icono: Icons.fact_check,
      titulo: 'Diagnóstico de calificaciones',
      detalle:
          'Duplicados, notas inválidas, materias fuera del plan y matrículas huérfanas.',
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const DiagCalifScreen()),
      ),
    ));
    hijos.add(_tarjeta(
      context: context,
      icono: Icons.calendar_month,
      titulo: 'Tablero de calendarización',
      detalle:
          'Avance de agenda por grupo: cursadas, en curso y por agendar.',
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const TableroCalendarizacionScreen()),
      ),
    ));

    secciones.forEach((titulo, items) {
      hijos.add(_encabezado(titulo));
      for (final it in items) {
        if (!_coincide(it[0] as String, titulo)) continue;
        final envia = _envianCorreos.contains(it[2] as String);
        hijos.add(Card(
          margin: EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: cessumGold.withValues(alpha: 0.15),
              child: Icon(it[1] as IconData, color: cessumGold),
            ),
            title: Text(it[0] as String,
                style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: envia
                ? const Text('Envía correos a alumnos · con vista previa dentro',
                    style: TextStyle(fontSize: 11.5, color: cessumRed, fontWeight: FontWeight.w600))
                : null,
            trailing: Icon(Icons.open_in_new, size: 18),
            onTap: () => _abrirConAviso(context, it[2] as String, it[0] as String),
          ),
        ));
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text('Herramientas de administración'),
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: EdgeInsets.all(16),
        children: [
          Text(
            'Pantallas y paneles del sistema. Las de arriba son nativas; las de '
            'las últimas secciones se abren en el navegador con tu sesión de '
            'administrador.',
            style: TextStyle(color: cessumMuted(context), fontSize: 13),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _q,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search),
              hintText: 'Buscar herramienta (p. ej. becas, respaldo, SIGA)',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              suffixIcon: _q.text.isEmpty
                  ? null
                  : IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() => _q.clear())),
            ),
          ),
          ...hijos,
        ],
      ),
    );
  }
}

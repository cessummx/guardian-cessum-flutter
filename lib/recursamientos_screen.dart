import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';   // (5-oct-2026) copiar cuenta y CLABE
import 'dart:html' as html;

import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

// =====================================================================
//  (5-oct-2026) UNA SOLA REGLA PARA «FALTA PAGAR», la misma del panel de
//  administración: la solicitud no está rechazada ni cancelada, el pago no
//  está verificado y no hay comprobante. NO depende del costo: antes, si el
//  costo quedaba en 0, la pantalla escondía el pago mientras el panel la
//  marcaba «falta de pago».
// =====================================================================
bool debePagarRecurso(Map<String, dynamic> s) {
  final e = (s['estado'] ?? '').toString().toLowerCase();
  if (e.contains('rechaz') || e.contains('cancel')) return false;
  // Igual que el panel: una solicitud de INTERÉS (sin grupo agendado) todavía no se paga, y una ya matriculada tampoco.
  if (e.contains('inter') || e.contains('matricul')) return false;
  if (s['pagoVerificado'] == true) return false;
  return (s['comprobante'] ?? '').toString().isEmpty;
}

/// Sube el comprobante de una solicitud. Devuelve la respuesta del Guardián, o null si se canceló.
/// La usan la lista y el detalle: una sola forma de subirlo.
Future<Map<String, dynamic>?> subirComprobanteRecursamiento(String id) async {
  final input = html.FileUploadInputElement()..accept = 'application/pdf,image/*';
  input.click();
  await input.onChange.first;
  if (input.files == null || input.files!.isEmpty) return null;
  final file = input.files!.first;
  if (file.size > 8 * 1024 * 1024) {
    return {'ok': false, 'error': 'El archivo pesa más de 8 MB. Sube una foto más ligera o un PDF.'};
  }
  final reader = html.FileReader();
  reader.readAsDataUrl(file);
  await reader.onLoad.first;
  final dataUrl = reader.result as String;
  final coma = dataUrl.indexOf(',');
  if (coma < 0) return {'ok': false, 'error': 'No se pudo leer el archivo.'};
  final resp = await http.post(
    Uri.parse(guardianUrl),
    headers: {'Content-Type': 'text/plain;charset=utf-8'},
    body: jsonEncode({'accion': 'recurso_comprobante', 'id': id, 'base64': dataUrl.substring(coma + 1), 'mime': file.type.isNotEmpty ? file.type : 'application/pdf'}),
  );
  return jsonDecode(resp.body) as Map<String, dynamic>;
}

/// Portal del alumno para RECURSAMIENTOS.
/// Muestra las materias que tiene pendientes de acreditar (calificación menor
/// al umbral) y le permite SOLICITAR su recursamiento. También lista las
/// solicitudes que ya envió, con su estado.
///
/// (ago-27) LO QUE SIGUE DE "SOLICITAR" YA NO ES UN CALLEJÓN.
/// Antes, al enviar la solicitud el alumno volvía a la misma lista y solo
/// veía una etiqueta "Pendiente". No sabía qué faltaba, cuánto pagar, ni
/// cómo comprobar el pago: el trámite se terminaba de acordar por WhatsApp.
/// Ahora, al solicitar se abre el DETALLE de la solicitud, con la materia,
/// el avance paso por paso, el pago y la carga del comprobante.
///
/// Conecta con el Guardián:
///   GET  recursamientos_alumno   (matricula / correo)
///   GET  recurso_costo           (matricula)
///   POST solicitar_recursamiento (materia, clave, etc.)
///   POST recurso_comprobante     (id, base64, mime)
class RecursamientosScreen extends StatefulWidget {
  final String matricula;
  final String correo;
  final String nombre;
  final String programa;
  final String generacion;

  const RecursamientosScreen({
    super.key,
    required this.matricula,
    this.correo = '',
    this.nombre = '',
    this.programa = '',
    this.generacion = '',
  });

  @override
  State<RecursamientosScreen> createState() => _RecursamientosScreenState();
}

class _RecursamientosScreenState extends State<RecursamientosScreen> {
  bool _cargando = true;

  /// Costo, si está al corriente y si puede solicitar. Lo sirve el backend
  /// para poder cambiar la regla sin recompilar.
  Map<String, dynamic>? _costo;
  // (5-oct-2026) A dónde pagar (antes solo lo veía la autogestiva) y el teléfono de dudas.
  Map<String, dynamic> _pagoDatos = {};
  // (5-oct-2026) Máximo dos recursamientos simultáneos (lineamiento de Vicerrectoría).
  Map<String, dynamic> _enCurso = {};
  String _telDudas = '642 130 5193';
  String? _error;

  /// (ago-27) El valor por omisión era 8 y contradecía al backend, que manda
  /// 7. Cuando la petición del costo tardaba, el alumno alcanzaba a leer
  /// "se acredita con 8 o más", que no es la regla de CESSUM. La escala del
  /// acta es de 6 a 10 y el 6 reprueba.
  int _umbral = 7;

  List<Map<String, dynamic>> _reprobadas = [];
  List<Map<String, dynamic>> _solicitudes = [];
  // (24-sep) Reglas de inscripción y la materia autogestiva del programa.
  String _reglaInscripcion = '';
  bool _esMaestriaEducacion = false;
  Map<String, dynamic>? _autogUsado;

  /* (22-sep) SOLICITAR CUALQUIER MATERIA DEL PLAN, NO SOLO LA REPROBADA.
     Solo se podía pedir lo que apareciera reprobado en calificaciones. Quien
     necesitaba volver a cursar una materia por otra razón —se dio de baja a
     media materia, la trae arrastrando, quiere reponerla antes de titularse—
     no tenía por dónde pedirlo, y por lo tanto no quedaba registrado: cuando
     se abre el grupo, el aviso solo le llega a quien solicitó.
     Ahora se ofrece el plan completo, con las reprobadas sugeridas arriba.
     Todas llegan igual al panel y se valoran una por una. */
  List<Map<String, dynamic>> _plan = [];

  /* (24-sep) RECURSAMIENTO AUTOGESTIVO. Solo aparece si Vicerrectoría se lo
     habilitó: el alumno abre el curso puntual, hace las actividades a su
     ritmo y al terminar toca la campanita para que lo revisen. */
  List<Map<String, dynamic>> _autog = [];
  final Set<String> _autogEnviando = {};

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  // Llave por materia, igual que en el backend (clave si existe; si no, nombre).
  String _keyMateria(String clave, String denom) {
    String n(String s) {
      s = s.trim().toLowerCase();
      const con = 'áàäâéèëêíìïîóòöôúùüûñ';
      const sin = 'aaaaeeeeiiiioooouuuun';
      for (var i = 0; i < con.length; i++) {
        s = s.replaceAll(con[i], sin[i]);
      }
      return s.replaceAll(RegExp(r'\s+'), ' ');
    }

    final c = n(clave);
    if (c.isNotEmpty) return 'C:$c';
    return 'D:${n(denom)}';
  }

  Future<void> _cargar() async {
    _cargarAutog();
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      // (ago-20) Se consulta el COSTO junto con la lista. El alumno tiene
      // que saber cuánto va a pagar ANTES de solicitar: enterarse después es
      // la forma más segura de que se sienta engañado y no vuelva.
      http
          .get(Uri.parse(guardianUrl).replace(queryParameters: {
            'accion': 'recurso_costo',
            'matricula': widget.matricula,
          }))
          .timeout(const Duration(seconds: 30))
          .then((rc) {
        if (!mounted) return;
        try {
          final d = jsonDecode(rc.body) as Map<String, dynamic>;
          if (d['ok'] == true) setState(() => _costo = d);
        } catch (_) {}
      }).catchError((_) {});

      // El plan de estudios, para poder pedir cualquier materia. Va aparte:
      // si esta consulta falla, la pantalla funciona como siempre.
      http
          .get(Uri.parse(guardianUrl).replace(queryParameters: {
            'accion': 'avance_plan',
            'matricula': widget.matricula,
            'programa': widget.programa,
            'generacion': widget.generacion,
          }))
          .timeout(const Duration(seconds: 40))
          .then((rp) {
        if (!mounted) return;
        try {
          final d = jsonDecode(rp.body) as Map<String, dynamic>;
          if (d['ok'] != true) return;
          final lista = <Map<String, dynamic>>[];
          for (final c in (d['ciclos'] as List<dynamic>? ?? [])) {
            final ciclo = Map<String, dynamic>.from(c as Map);
            for (final m in (ciclo['materias'] as List<dynamic>? ?? [])) {
              final mm = Map<String, dynamic>.from(m as Map);
              lista.add({
                'materia': (mm['materia'] ?? '').toString(),
                'clave': (mm['clave'] ?? '').toString(),
                'ciclo': (ciclo['ciclo'] ?? '').toString(),
                'estado': (mm['estado'] ?? '').toString(),
                'cal': (mm['cal'] ?? '').toString(),
                'programa': (d['programa'] ?? widget.programa).toString(),
                'generacion': (d['generacion'] ?? widget.generacion).toString(),
              });
            }
          }
          setState(() => _plan = lista);
        } catch (_) {}
      }).catchError((_) {});

      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'recursamientos_alumno',
        'matricula': widget.matricula,
        'correo': widget.correo,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] != true) {
        setState(() {
          _cargando = false;
          _error =
              (data['error'] ?? 'No se pudo cargar la información').toString();
        });
        return;
      }
      setState(() {
        _cargando = false;
        _umbral = (data['umbral'] is num) ? (data['umbral'] as num).toInt() : 7;
        _reprobadas = (data['reprobadas'] as List<dynamic>? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _solicitudes = (data['solicitudes'] as List<dynamic>? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _reglaInscripcion = '${data['reglaInscripcion'] ?? ''}';
        _pagoDatos = data['pagoDatos'] is Map ? Map<String, dynamic>.from(data['pagoDatos'] as Map) : {};
        _enCurso = data['recursamientosEnCurso'] is Map ? Map<String, dynamic>.from(data['recursamientosEnCurso'] as Map) : {};
        if ('${data['telefonoDudas'] ?? ''}'.isNotEmpty) _telDudas = '${data['telefonoDudas']}';
        _esMaestriaEducacion = data['esMaestriaEducacion'] == true;
        _autogUsado = data['autogestivoUsado'] is Map
            ? Map<String, dynamic>.from(data['autogestivoUsado'] as Map)
            : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo conectar. Revisa tu internet e intenta de nuevo.';
      });
    }
  }

  // Conjunto de materias con solicitud PENDIENTE (para no duplicar).
  Set<String> _pendientesSet() {
    final set = <String>{};
    for (final s in _solicitudes) {
      final estado = (s['estado'] ?? '').toString().toLowerCase();
      // (22-sep) También la ya matriculada: mientras la recursa, no se vuelve
      // a pedir. El Guardián tampoco lo acepta.
      if (estado == 'pendiente' || estado.contains('matricul')) {
        set.add(_keyMateria(
            (s['clave'] ?? '').toString(), (s['materia'] ?? '').toString()));
      }
    }
    return set;
  }

  /// Abre el detalle de una solicitud. Al volver se recarga, porque adentro
  /// se puede haber subido el comprobante.
  /// (5-oct-2026) Subir el comprobante desde la lista, sin entrar al detalle.
  final Set<String> _subiendo = {};
  Future<void> _subirDesdeLista(Map<String, dynamic> s) async {
    final id = '${s['id'] ?? ''}';
    if (id.isEmpty) return;
    setState(() => _subiendo.add(id));
    Map<String, dynamic>? d;
    try {
      d = await subirComprobanteRecursamiento(id);
    } catch (e) {
      d = {'ok': false, 'error': '$e'};
    }
    if (!mounted) return;
    setState(() => _subiendo.remove(id));
    if (d == null) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: d['ok'] == true ? const Color(0xFF1E7B34) : cessumRed,
        content: Text(d['ok'] == true ? 'Comprobante recibido. Vicerrectoría ya tiene el aviso.' : '${d['error'] ?? 'No se pudo subir.'}')));
    if (d['ok'] == true) await _cargar();
  }

  Future<void> _abrirDetalle(Map<String, dynamic> s) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DetalleRecursamientoScreen(
          solicitud: s,
          costo: _costo,
          matricula: widget.matricula,
          correo: widget.correo,
        ),
      ),
    );
    if (mounted) await _cargar();
  }

  /// (24-sep) Las opciones agendadas de una materia, cada una con sus fechas,
  /// su duración y hasta cuándo se puede inscribir.
  List<Widget> _opcionesDe(Map<String, dynamic> m, bool yaPendiente, bool bloqueado) {
    final ops = ((m['opciones'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    if (ops.isEmpty) return const [];
    return [
      const SizedBox(height: 8),
      Text(ops.length == 1 ? 'Opción agendada' : 'Opciones agendadas',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
      for (final o in ops)
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: (o['abierta'] == true ? const Color(0xFF1E7D32) : Colors.grey).withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
                color: (o['abierta'] == true ? const Color(0xFF1E7D32) : Colors.grey).withValues(alpha: 0.35)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Grupo ${o['grupo']}${'${o['generacion'] ?? ''}'.isNotEmpty ? ' (${o['generacion']})' : ''}'
                '${'${o['dia'] ?? ''}'.isNotEmpty ? ' · ${o['dia']}' : ''}${'${o['hora'] ?? ''}'.isNotEmpty ? ' ${o['hora']}' : ''}',
                style: const TextStyle(fontSize: 12.8, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text('Del ${o['inicio']} al ${o['termino']}${o['semanas'] != null ? ' · ${o['semanas']} semanas' : ''}',
                style: const TextStyle(fontSize: 12.5)),
            const SizedBox(height: 2),
            Text(
              o['abierta'] == true
                  ? 'Inscripción abierta hasta el ${o['cierre']}'
                  : 'Inscripción cerrada (cerró el ${o['cierre']})',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: o['abierta'] == true ? const Color(0xFF1E7D32) : Colors.grey),
            ),
            if (o['obligatoria'] == true)
              const Padding(
                padding: EdgeInsets.only(top: 3),
                child: Text('Asistencia obligatoria a todas las sesiones del grupo.',
                    style: TextStyle(fontSize: 12, color: cessumRed, fontWeight: FontWeight.w600)),
              ),
            if (o['abierta'] == true && !yaPendiente) ...[
              const SizedBox(height: 6),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor: cessumRed, foregroundColor: Colors.white, visualDensity: VisualDensity.compact),
                onPressed: bloqueado ? null : () => _solicitar(m, opcion: o),
                icon: Icon(bloqueado ? Icons.lock_outline : Icons.how_to_reg, size: 16),
                label: Text(bloqueado ? 'Ponte al corriente para solicitar' : 'Elegir esta opción'),
              ),
            ],
          ]),
        ),
    ];
  }

  /// (24-sep) Solicitud de la materia en modalidad autogestiva: una por
  /// programa y solo de una reprobada. La decide Vicerrectoría.
  Future<void> _solicitarAutogestiva(Map<String, dynamic> m) async {
    final motivo = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Modalidad autogestiva\n${m['materia'] ?? ''}', style: const TextStyle(fontSize: 16)),
        content: SizedBox(
          width: 440,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text(
              'Trabajarías la materia a tu ritmo, en un curso del Aula y en un periodo definido. '
              'Solo puedes solicitar UNA materia autogestiva en todo tu programa. Vicerrectoría revisará '
              'tu solicitud y te avisará en la campanita.',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: motivo,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
                labelText: '¿Por qué la necesitas en esta modalidad?',
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Enviar solicitud'),
          ),
        ],
      ),
    );
    final texto = motivo.text.trim();
    motivo.dispose();
    if (ok != true || !mounted) return;
    try {
      final r = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'autogestivo_solicitar',
                'matricula': widget.matricula,
                'clave': '${m['clave'] ?? ''}',
                'materia': '${m['materia'] ?? ''}',
                'motivo': texto,
              }))
          .timeout(const Duration(seconds: 60));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (!mounted) return;
      _aviso('${d['ok'] == true ? d['mensaje'] : (d['error'] ?? 'No se pudo enviar.')}');
      if (d['ok'] == true) {
        await _cargar();
        await _cargarAutog();
      }
    } catch (_) {
      if (mounted) _aviso('No se pudo conectar. Intenta de nuevo.');
    }
  }

  Future<void> _solicitar(Map<String, dynamic> m, {Map<String, dynamic>? opcion}) async {
    // (2-oct-2026) PREINSCRIPCIÓN DE INTERÉS — si la materia no está
    // ofertada todavía (no hay opción que elegir), este mismo diálogo sirve
    // para dejar constancia de que el alumno la quiere recursar: el backend
    // la registra como "Interés" en vez de "Pendiente", Vicerrectoría la ve
    // en el panel, y decide si abre un grupo, la ofrece autogestiva, o
    // espera. El aviso real de "ya se puede" llega solo cuando se notifique
    // el inicio de un grupo de esa materia.
    final esInteres = opcion == null && m['ofertada'] != true;
    final comentarioCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
            (esInteres ? 'Avisarme cuando se oferte\n' : 'Solicitar recursamiento\n') +
                '${m['materia'] ?? ''}',
            style: const TextStyle(fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (opcion != null) ...[
              Text(
                'Grupo ${opcion['grupo']} · ${opcion['dia'] ?? ''} ${opcion['hora'] ?? ''}\n'
                'Del ${opcion['inicio']} al ${opcion['termino']}'
                '${opcion['semanas'] != null ? ' · ${opcion['semanas']} semanas' : ''}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, height: 1.35),
              ),
              if (opcion['obligatoria'] == true)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text('La asistencia a todas las sesiones es obligatoria.',
                      style: TextStyle(fontSize: 12.5, color: cessumRed, fontWeight: FontWeight.w600)),
                ),
              const SizedBox(height: 8),
            ],
            Text(
              esInteres
                  ? 'Esta materia no está agendada en este momento. Registraremos tu '
                      'interés: Vicerrectoría te avisará por correo en cuanto se abra un '
                      'grupo para cursarla.'
                  : 'Vicerrectoría Académica revisará tu solicitud y te contactará '
                      'para acordar los detalles del recursamiento.',
              style: const TextStyle(fontSize: 13, height: 1.35),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: comentarioCtrl,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: 'Comentario (opcional)',
                hintText: 'Ej. disponibilidad de horario, dudas, etc.',
                isDense: true,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(esInteres ? 'Registrar mi interés' : 'Enviar solicitud'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final payload = <String, dynamic>{
      'accion': 'solicitar_recursamiento',
      'matricula': widget.matricula,
      'nombre': widget.nombre,
      'correo': widget.correo,
      'programa': (m['programa'] ?? widget.programa).toString(),
      'generacion': (m['generacion'] ?? widget.generacion).toString(),
      'materia': (m['materia'] ?? '').toString(),
      'clave': (m['clave'] ?? '').toString(),
      'calificacion': m['calificacion'],
      'comentario': comentarioCtrl.text.trim(),
      if (opcion != null) 'opcionFila': opcion['fila'],
    };
    try {
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode(payload))
          .timeout(const Duration(seconds: 25));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] != true) {
        _aviso((data['error'] ?? 'No se pudo enviar la solicitud').toString());
        return;
      }
      _aviso(esInteres
          ? 'Interés registrado. Te avisaremos en cuanto se abra un grupo.'
          : 'Solicitud enviada. Vicerrectoría te contactará.');

      // (ago-27) SE ABRE EL DETALLE, NO SE REGRESA A LA LISTA.
      // Lo que sigue de solicitar es pagar, y el alumno no tiene por qué
      // adivinar dónde está eso. Se recarga primero para traer el folio, el
      // costo congelado y el estado que acaba de crear el backend.
      final nuevoId = (data['id'] ?? '').toString();
      await _cargar();
      if (!mounted) return;
      if (nuevoId.isNotEmpty) {
        Map<String, dynamic>? recien;
        for (final s in _solicitudes) {
          if ((s['id'] ?? '').toString() == nuevoId) {
            recien = s;
            break;
          }
        }
        if (recien != null) await _abrirDetalle(recien);
      }
    } catch (_) {
      if (mounted) _aviso('No se pudo enviar. Intenta de nuevo.');
    }
  }

  void _aviso(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// EL COSTO Y EL REQUISITO, ANTES DE TODO LO DEMÁS.
  ///
  /// Va arriba porque son las dos preguntas que trae quien abre esta
  /// pantalla: cuánto cuesta y si puede. Enterrarlo abajo obliga a solicitar
  /// a ciegas.
  Widget _tarjetaCosto() {
    final c = _costo;
    if (c == null) return const SizedBox.shrink();
    final puede = c['puedeSolicitar'] == true;
    final costo = (c['costoRecursamiento'] as num?)?.toInt() ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: puede
            ? cessumGold.withValues(alpha: 0.08)
            : cessumRed.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
            color: (puede ? cessumGold : cessumRed).withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (costo > 0) ...[
            Text('COSTO POR MATERIA',
                style: TextStyle(
                    fontSize: 9.5,
                    letterSpacing: .9,
                    fontWeight: FontWeight.w800,
                    color: cessumGold)),
            Text('\$$costo',
                style: const TextStyle(
                    fontSize: 30, fontWeight: FontWeight.w800, height: 1.1)),
            const SizedBox(height: 4),
            // Esto es lo que más confunde a los becados. Se dice sin rodeos.
            Text('${c['comoSeCalcula'] ?? ''}',
                style: const TextStyle(fontSize: 12.5, height: 1.5)),
          ],
          if (!puede) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: cessumRed.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(9),
              ),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.info_outline, size: 17, color: cessumRed),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                      '${c['porQueNo'] ?? 'Por ahora no puedes solicitar.'}',
                      style: const TextStyle(fontSize: 12.5, height: 1.45)),
                ),
              ]),
            ),
          ],
          const SizedBox(height: 10),
          Row(children: [
            const Icon(Icons.phone, size: 15, color: Colors.black54),
            const SizedBox(width: 6),
            Expanded(
              child: Text('${c['dudas'] ?? ''}',
                  style: const TextStyle(fontSize: 12, color: Colors.black54)),
            ),
          ]),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Recursamientos'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
            onPressed: _cargando ? null : _cargar,
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : _error != null
              ? _vistaError()
              : RefreshIndicator(
                  color: cessumRed,
                  onRefresh: _cargar,
                  child: _contenido(),
                ),
    );
  }

  Widget _vistaError() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 40),
        Icon(Icons.cloud_off, size: 48, color: cessumFaint(context)),
        const SizedBox(height: 12),
        Text(_error ?? 'Error',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: Colors.black54)),
        const SizedBox(height: 16),
        Center(
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: _cargar,
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar'),
          ),
        ),
      ],
    );
  }

  // ---------------- Recursamiento autogestivo ----------------

  Future<void> _cargarAutog() async {
    try {
      final r = await http
          .get(Uri.parse(guardianUrl).replace(queryParameters: {
            'accion': 'autogestivo_alumno',
            'matricula': widget.matricula,
          }))
          .timeout(const Duration(seconds: 40));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] == true && mounted) {
        setState(() => _autog = ((d['items'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList());
      }
    } catch (_) {}
  }

  /// La CAMPANITA: avisa a Vicerrectoría que terminó las actividades.
  Future<void> _avisarTermine(Map<String, dynamic> a) async {
    final id = '${a['id']}';
    final nota = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.notifications_active, color: cessumGold),
          SizedBox(width: 8),
          Expanded(child: Text('¿Ya terminaste?', style: TextStyle(fontSize: 17))),
        ]),
        content: SizedBox(
          width: 440,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Vas a avisar a Vicerrectoría que terminaste TODAS las actividades de «${a['materia']}». '
                'Revisa antes en el curso que cada actividad quedó enviada.',
                style: const TextStyle(fontSize: 13.5, height: 1.4)),
            const SizedBox(height: 12),
            TextField(
              controller: nota,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
                labelText: 'Comentario para Vicerrectoría (opcional)',
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Todavía no')),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: cessumRed),
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.notifications_active, size: 18),
            label: const Text('Sí, avisar'),
          ),
        ],
      ),
    );
    final texto = nota.text.trim();
    nota.dispose();
    if (ok != true || !mounted) return;
    setState(() => _autogEnviando.add(id));
    String msj;
    bool exito = false;
    try {
      final r = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({'accion': 'autogestivo_terminar', 'id': id, 'nota': texto}))
          .timeout(const Duration(seconds: 60));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      exito = d['ok'] == true;
      msj = '${exito ? (d['mensaje'] ?? 'Aviso enviado.') : (d['error'] ?? 'No se pudo enviar el aviso.')}';
    } catch (_) {
      msj = 'No se pudo conectar. Intenta de nuevo.';
    }
    if (!mounted) return;
    setState(() => _autogEnviando.remove(id));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: exito ? const Color(0xFF1E7F52) : cessumRed,
      duration: const Duration(seconds: 6),
      content: Text(msj),
    ));
    await _cargarAutog();
  }

  /// Sube el comprobante de pago del recursamiento autogestivo. La IA lo lee
  /// y, si corresponde, el curso se abre en ese momento.
  Future<void> _subirComprobanteAutog(Map<String, dynamic> a) async {
    final id = '${a['id']}';
    try {
      final input = html.FileUploadInputElement()..accept = 'application/pdf,image/*';
      input.click();
      await input.onChange.first;
      if (input.files == null || input.files!.isEmpty) return;
      final file = input.files!.first;
      if (file.size > 8 * 1024 * 1024) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            backgroundColor: cessumRed,
            content: Text('El archivo pesa más de 8 MB. Sube una foto más ligera o un PDF.')));
        return;
      }
      final reader = html.FileReader();
      reader.readAsDataUrl(file);
      await reader.onLoad.first;
      final dataUrl = reader.result as String;
      final coma = dataUrl.indexOf(',');
      if (coma < 0) return;
      if (!mounted) return;
      setState(() => _autogEnviando.add(id));
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Subiendo y revisando tu comprobante…')));
      final r = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'autogestivo_comprobante',
                'id': id,
                'base64': dataUrl.substring(coma + 1),
                'mime': file.type.isNotEmpty ? file.type : 'application/pdf',
              }))
          .timeout(const Duration(seconds: 120));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() => _autogEnviando.remove(id));
      final validado = d['ok'] == true && d['validado'] == true;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(children: [
            Icon(validado ? Icons.verified : (d['ok'] == true ? Icons.hourglass_top : Icons.error_outline),
                color: validado ? const Color(0xFF1E7F52) : (d['ok'] == true ? cessumGold : cessumRed)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(validado ? 'Pago validado' : (d['ok'] == true ? 'Comprobante recibido' : 'No se pudo subir'),
                  style: const TextStyle(fontSize: 17)),
            ),
          ]),
          content: Text('${d['ok'] == true ? (d['mensaje'] ?? '') : (d['error'] ?? 'Intenta de nuevo.')}'),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendido'))],
        ),
      );
      await _cargarAutog();
    } catch (e) {
      if (!mounted) return;
      setState(() => _autogEnviando.remove(id));
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(backgroundColor: cessumRed, content: Text('No se pudo subir el comprobante. Intenta de nuevo.')));
    }
  }

  Widget _seccionAutog() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: const [
        Icon(Icons.self_improvement, color: cessumRed, size: 20),
        SizedBox(width: 8),
        Expanded(
          child: Text('Recursamiento autogestivo',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: cessumRed)),
        ),
      ]),
      const SizedBox(height: 6),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cessumGold.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cessumGold.withValues(alpha: 0.35)),
        ),
        child: Text(
          'Cómo funciona:\n'
          '1. Realiza tu pago y sube el comprobante aquí mismo. Al validarse se te abre el curso.\n'
          '2. Toca «Abrir el curso» y entra con tu correo institucional.\n'
          '3. Realiza y envía TODAS las actividades dentro del periodo, a tu ritmo.\n'
          '4. Cuando termines, toca la campanita «Avisar que terminé».\n'
          '5. Vicerrectoría revisa tus actividades y te avisa el resultado en la campanita de avisos de la app.',
          style: TextStyle(fontSize: 12.5, height: 1.5, color: cessumMuted(context)),
        ),
      ),
      const SizedBox(height: 10),
      ..._autog.map(_tarjetaAutog),
      const SizedBox(height: 22),
    ]);
  }

  Widget _tarjetaAutog(Map<String, dynamic> a) {
    final estado = '${a['estado'] ?? 'Habilitado'}';
    final id = '${a['id']}';
    final link = '${a['link'] ?? ''}';
    final puedeAvisar = estado == 'Habilitado' || estado == 'Requiere ajustes';
    final porPagar = estado == 'Pendiente de pago';
    final pago = (a['pagoDatos'] is Map) ? Map<String, dynamic>.from(a['pagoDatos'] as Map) : <String, dynamic>{};
    final Color c = switch (estado) {
      'Aprobado' => const Color(0xFF1E7F52),
      'Por revisar' || 'Pago por revisar' => cessumGold,
      'Pendiente de pago' => const Color(0xFF6B7280),
      'Requiere ajustes' => cessumRed,
      _ => const Color(0xFF3B6EA8),
    };
    final texto = switch (estado) {
      'Por revisar' => 'Avisaste el ${a['termino']}. Vicerrectoría está revisando tus actividades.',
      'Aprobado' => 'Vicerrectoría revisó tus actividades y quedaron aprobadas.',
      'Requiere ajustes' => 'Vicerrectoría pide ajustes. Corrígelos en el curso y vuelve a tocar la campanita.',
      'Pendiente de pago' => 'Para empezar, realiza tu pago y sube el comprobante. Al validarse se te abre el curso.',
      'Pago por revisar' => 'Recibimos tu comprobante. Vicerrectoría lo está revisando y te avisará en la campanita.',
      'Solicitada' => 'Enviaste tu solicitud para cursarla en modalidad autogestiva. Vicerrectoría la está revisando y te avisará en la campanita.',
      'Rechazada' => 'Tu solicitud para cursarla en modalidad autogestiva no fue aprobada.',
      _ => 'Ya puedes trabajar en el curso. Cuando termines todo, toca la campanita.',
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.withValues(alpha: 0.45)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text('${a['materia'] ?? ''}',
                style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
            child: Text(estado, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: c)),
          ),
        ]),
        if ('${a['inicio'] ?? ''}'.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('Periodo: del ${a['inicio']} al ${a['fin']}',
              style: const TextStyle(fontSize: 12.8, fontWeight: FontWeight.w700)),
        ],
        const SizedBox(height: 6),
        Text(texto, style: TextStyle(fontSize: 12.8, height: 1.4, color: cessumMuted(context))),
        if (porPagar && pago.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: cessumGold.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: cessumGold.withValues(alpha: 0.35)),
            ),
            child: SelectableText(
              '${(a['costo'] as num? ?? 0) > 0 ? 'Costo: \$${a['costo']}\n' : ''}'
              'Transferencia a ${pago['banco']} · a nombre de ${pago['titular']}\n'
              'Cuenta: ${pago['cuenta']}\n'
              'CLABE: ${pago['clabe']}\n'
              'Concepto: ${pago['concepto']}',
              style: const TextStyle(fontSize: 12.8, height: 1.5),
            ),
          ),
        ],
        if ('${a['instrucciones'] ?? ''}'.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Indicaciones: ${a['instrucciones']}', style: const TextStyle(fontSize: 12.8, height: 1.4)),
        ],
        if ('${a['comentario'] ?? ''}'.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: c.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
            child: Text('Comentario de Vicerrectoría: ${a['comentario']}',
                style: const TextStyle(fontSize: 12.8, height: 1.4)),
          ),
        ],
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (porPagar)
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: cessumRed),
              onPressed: _autogEnviando.contains(id) ? null : () => _subirComprobanteAutog(a),
              icon: _autogEnviando.contains(id)
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.upload_file, size: 18),
              label: const Text('Subir comprobante'),
            ),
          if (link.isNotEmpty && estado != 'Aprobado')
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: cessumRed),
              onPressed: () => html.window.open(link, '_blank'),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('Abrir el curso'),
            ),
          if (puedeAvisar)
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: cessumGold, foregroundColor: Colors.white),
              onPressed: _autogEnviando.contains(id) ? null : () => _avisarTermine(a),
              icon: _autogEnviando.contains(id)
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.notifications_active, size: 18),
              label: const Text('Avisar que terminé'),
            ),
        ]),
      ]),
    );
  }

  // =====================================================================
  //  (5-oct-2026) PANTALLA SIMPLE. Arriba, UN solo recuadro «Tu siguiente
  //  paso» con la única acción que le toca al alumno (pagar y subir el
  //  comprobante, esperar la revisión, o inscribirse). Debajo, sus
  //  recursamientos en curso y, al final, las materias que puede recursar.
  //  Antes: siete bloques, la explicación del costo arriba y «Mis
  //  solicitudes» hasta abajo; el pago quedaba escondido en el detalle.
  // =====================================================================
  bool _activa(Map<String, dynamic> s) {
    final e = (s['estado'] ?? '').toString().toLowerCase();
    return !(e.contains('rechaz') || e.contains('cancel'));
  }

  Widget _contenido() {
    final pendientes = _pendientesSet();
    final activas = _solicitudes.where(_activa).toList();
    final historial = _solicitudes.where((s) => !_activa(s)).toList();
    final porRecursar = _reprobadas.where((m) => !pendientes.contains(_keyMateria((m['clave'] ?? '').toString(), (m['materia'] ?? '').toString()))).toList();
    final costoMateria = (_costo?['costoRecursamiento'] as num?)?.toInt() ?? 0;
    final bloqueado = _costo != null && _costo!['puedeSolicitar'] == false;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(widget.nombre.isNotEmpty ? widget.nombre : 'Matrícula ${widget.matricula}',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        if (widget.programa.isNotEmpty)
          Text('${widget.programa}${widget.generacion.isNotEmpty ? ' · ${widget.generacion}' : ''}',
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
        const SizedBox(height: 14),
        _siguientePaso(activas, porRecursar),
        if (activas.length > 1) ...[
          const SizedBox(height: 18),
          _titulo(Icons.history_edu, 'Tus recursamientos', cessumGold),
          ...activas.map(_tarjetaSolicitud),
        ],
        if (_autog.isNotEmpty) ...[const SizedBox(height: 8), _seccionAutog()],
        const SizedBox(height: 18),
        _titulo(Icons.assignment_late, porRecursar.isEmpty ? 'Materias por acreditar' : 'Materias que puedes recursar', cessumRed),
        if (_reprobadas.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              '${costoMateria > 0 ? 'Costo por materia: \$$costoMateria (la mitad de la colegiatura de lista, sin beca). ' : ''}'
              'Se acredita con $_umbral o más. ${_reglaInscripcion.isNotEmpty ? _reglaInscripcion : ''}',
              style: const TextStyle(fontSize: 12, height: 1.45, color: Colors.black54),
            ),
          ),
        if (_enCurso['alcanzado'] == true && porRecursar.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFF1565C0).withValues(alpha: 0.07), borderRadius: BorderRadius.circular(10)),
            child: Text(
              'Llevas ${_enCurso['total']} de ${_enCurso['limite']} recursamientos en curso, que es el máximo a la vez. '
              'En cuanto acredites uno podrás inscribirte al siguiente. Mientras, sí puedes pedir que te avisemos cuando se abra cada materia.',
              style: const TextStyle(fontSize: 12.5, height: 1.45),
            ),
          ),
        if (bloqueado)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: cessumRed.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(10)),
            child: Text('${_costo!['porQueNo'] ?? 'Para recursar hay que estar al corriente en los pagos.'}',
                style: const TextStyle(fontSize: 12.5, height: 1.45)),
          ),
        if (_reprobadas.isEmpty)
          _tarjetaVacia(icon: Icons.emoji_events, texto: 'No tienes materias pendientes de acreditar. ¡Excelente trabajo!')
        else if (porRecursar.isEmpty)
          const Text('Todas tus materias pendientes ya tienen un trámite en curso (arriba).', style: TextStyle(fontSize: 12.5, color: Colors.black54))
        else
          ...porRecursar.map((m) => _tarjetaReprobada(m, false)),
        const SizedBox(height: 10),
        _tarjetaOtraMateria(),
        if (historial.isNotEmpty)
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('Solicitudes anteriores (${historial.length})', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              children: historial.map(_tarjetaSolicitud).toList(),
            ),
          ),
        const SizedBox(height: 30),
      ],
    );
  }

  Widget _titulo(IconData i, String t, Color c) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Icon(i, color: c, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(t, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: c))),
        ]),
      );

  /// El recuadro de arriba: lo ÚNICO que le toca hacer ahora.
  Widget _siguientePaso(List<Map<String, dynamic>> activas, List<Map<String, dynamic>> porRecursar) {
    Map<String, dynamic>? primero(bool Function(Map<String, dynamic>) f) {
      for (final s in activas) { if (f(s)) return s; }
      return null;
    }
    String est(Map<String, dynamic> s) => (s['estado'] ?? '').toString().toLowerCase();
    final pagar = primero(debePagarRecurso);
    final enRevision = primero((s) => s['pagoVerificado'] != true && '${s['comprobante'] ?? ''}'.isNotEmpty);
    final cursando = primero((s) => est(s).contains('matricul') || '${s['grupoAsignado'] ?? ''}'.isNotEmpty);
    final pagadoSinGrupo = primero((s) => s['pagoVerificado'] == true && '${s['grupoAsignado'] ?? ''}'.isEmpty && !est(s).contains('matricul'));
    final interes = primero((s) => est(s).contains('inter'));

    if (pagar != null) return _heroPago(pagar);
    if (enRevision != null) {
      return _hero(Icons.hourglass_top, cessumGold, 'Estamos revisando tu pago',
          'Recibimos tu comprobante de «${enRevision['materia']}». Vicerrectoría lo revisa y te avisa en la campanita. No tienes que hacer nada más por ahora.',
          [TextButton(onPressed: () => _abrirDetalle(enRevision), child: const Text('Ver mi trámite'))]);
    }
    if (pagadoSinGrupo != null) {
      return _hero(Icons.verified, const Color(0xFF1E7B34), 'Pago verificado',
          'Tu pago de «${pagadoSinGrupo['materia']}» ya quedó verificado. Vicerrectoría te asigna tu grupo y te avisa en la campanita.',
          [TextButton(onPressed: () => _abrirDetalle(pagadoSinGrupo), child: const Text('Ver mi trámite'))]);
    }
    if (cursando != null) {
      final g = '${cursando['grupoAsignado'] ?? ''}';
      return _hero(Icons.school, const Color(0xFF1E7B34), 'Estás recursando «${cursando['materia']}»',
          g.isNotEmpty ? 'Quedaste en: $g. Entra a tu aula como en cualquier materia.' : 'Ya estás inscrito. Entra a tu aula como en cualquier materia.',
          [TextButton(onPressed: () => _abrirDetalle(cursando), child: const Text('Ver mi trámite'))]);
    }
    if (interes != null) {
      return _hero(Icons.notifications_active_outlined, const Color(0xFF1565C0), 'Te avisamos cuando se abra un grupo',
          'Registraste tu interés en «${interes['materia']}». Hoy no hay grupo agendado; en cuanto se abra uno te llega el aviso y entonces haces tu pago. Todavía no pagues nada.',
          const []);
    }
    final ofertadas = porRecursar.where((m) => m['ofertada'] == true).length;
    if (porRecursar.isEmpty) {
      return _hero(Icons.emoji_events, const Color(0xFF1E7B34), 'Nada pendiente', 'No tienes trámites de recursamiento en curso.', const []);
    }
    return _hero(Icons.touch_app, cessumRed,
        ofertadas > 0 ? 'Puedes inscribirte a ${ofertadas == 1 ? 'una materia' : '$ofertadas materias'}' : 'Ninguna de tus materias está agendada hoy',
        ofertadas > 0
            ? 'Abajo elige la materia y la fecha que te acomode. Después de inscribirte, aquí mismo te diremos cuánto pagar y dónde.'
            : 'Abajo puedes pedir que te avisemos cuando se agende cada una.',
        const []);
  }

  Widget _hero(IconData icono, Color c, String titulo, String texto, List<Widget> acciones, {List<Widget> cuerpo = const []}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.withValues(alpha: 0.45), width: 1.4),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('TU SIGUIENTE PASO', style: TextStyle(fontSize: 10, letterSpacing: 1.2, fontWeight: FontWeight.w800, color: c)),
          const SizedBox(height: 6),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icono, color: c, size: 26),
            const SizedBox(width: 10),
            Expanded(child: Text(titulo, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, height: 1.25))),
          ]),
          const SizedBox(height: 8),
          Text(texto, style: const TextStyle(fontSize: 13.5, height: 1.45)),
          ...cuerpo,
          if (acciones.isNotEmpty) ...[const SizedBox(height: 6), Wrap(spacing: 8, children: acciones)],
        ]),
      );

  Widget _filaCopiar(String etiqueta, String valor) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(children: [
          SizedBox(width: 74, child: Text(etiqueta, style: const TextStyle(fontSize: 12, color: Colors.black54))),
          Expanded(child: SelectableText(valor, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
          IconButton(
            tooltip: 'Copiar',
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            onPressed: () {
              Clipboard.setData(ClipboardData(text: valor));
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$etiqueta copiado')));
            },
            icon: const Icon(Icons.copy),
          ),
        ]),
      );

  /// Pagar: cuánto, a dónde, y el botón para subir el comprobante. Todo en el mismo recuadro.
  Widget _heroPago(Map<String, dynamic> s) {
    final costo = (s['costo'] as num?)?.toInt() ?? 0;
    final b = _pagoDatos;
    final id = '${s['id'] ?? ''}';
    final subiendo = _subiendo.contains(id);
    return _hero(
      Icons.payments_outlined,
      cessumRed,
      costo > 0 ? 'Paga \$$costo y sube tu comprobante' : 'Paga tu recursamiento y sube tu comprobante',
      'Es para recursar «${s['materia']}». ${costo > 0 ? '' : 'El monto no quedó registrado: confírmalo al $_telDudas antes de pagar. '}'
          'En cuanto subas el comprobante, Vicerrectoría lo revisa y te asigna tu grupo.',
      [
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: cessumRed, minimumSize: const Size(0, 46)),
          onPressed: subiendo ? null : () => _subirDesdeLista(s),
          icon: subiendo
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.upload_file),
          label: Text(subiendo ? 'Subiendo…' : 'Ya pagué: subir comprobante', style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
        ),
        TextButton(onPressed: () => _abrirDetalle(s), child: const Text('Ver mi trámite')),
      ],
      cuerpo: [
        if (b.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 6, 4, 10),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (costo > 0) _filaCopiar('Monto', '$costo'),
              _filaCopiar('Banco', '${b['banco'] ?? ''} · ${b['titular'] ?? ''}'),
              _filaCopiar('Cuenta', '${b['cuenta'] ?? ''}'),
              _filaCopiar('CLABE', '${b['clabe'] ?? ''}'),
              _filaCopiar('Concepto', 'Recursamiento ${widget.nombre.isNotEmpty ? widget.nombre : widget.matricula}'),
            ]),
          ),
        ],
        const SizedBox(height: 6),
        Text('Sube una foto o PDF donde se vean la fecha y el monto. Dudas: $_telDudas.', style: const TextStyle(fontSize: 11.5, color: Colors.black54)),
      ],
    );
  }

  /// (ago-27) UN SOLO AVISO ARRIBA CUANDO HAY ALGO QUE HACER.
  ///
  /// Si tiene una solicitud aceptada y sin comprobante, eso es lo único que
  /// detiene su recursamiento. Enterarlo hasta abajo, dentro de una tarjeta,
  /// es la manera más eficaz de que el trámite se quede parado semanas.
  Widget _avisoPendienteDePago() {
    // (5-oct-2026) La misma regla del panel de administración; no depende del costo.
    final porPagar = _solicitudes.where(debePagarRecurso).toList();
    if (porPagar.isEmpty) return const SizedBox.shrink();

    final una = porPagar.length == 1;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: cessumGold.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: cessumGold.withValues(alpha: 0.5)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.upload_file, size: 19, color: Color(0xFFB07D12)),
        const SizedBox(width: 9),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              una
                  ? 'Falta tu comprobante de pago'
                  : 'Faltan ${porPagar.length} comprobantes de pago',
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, height: 1.3),
            ),
            const SizedBox(height: 3),
            Text(
              'Tu recursamiento no avanza hasta que subas el comprobante'
              '${una && ((porPagar.first['costo'] as num?) ?? 0) > 0 ? ' de \$${porPagar.first['costo']}' : ''}. '
              'Súbelo aquí mismo: foto o PDF donde se vean la fecha y el monto.',
              style: TextStyle(fontSize: 12, height: 1.4, color: Colors.black54),
            ),
            const SizedBox(height: 7),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFB07D12),
                side: BorderSide(color: cessumGold.withValues(alpha: .6)),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: _subiendo.contains('${porPagar.first['id']}') ? null : () => _subirDesdeLista(porPagar.first),
              icon: const Icon(Icons.upload_file, size: 15),
              label: Text(
                  una
                      ? 'Subir comprobante'
                      : 'Subir el de ${porPagar.first['materia'] ?? ''}',
                  style: const TextStyle(fontSize: 12)),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _encabezado() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFBF7EF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cessumGold.withValues(alpha: 0.4)),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.nombre.isNotEmpty
                ? widget.nombre
                : 'Matrícula ${widget.matricula}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          if (widget.programa.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '${widget.programa}'
                '${widget.generacion.isNotEmpty ? " · ${widget.generacion}" : ""}',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ),
          const SizedBox(height: 8),
          Text(
            'Una materia se considera acreditada con $_umbral o más. '
            'Aquí puedes solicitar recursar las que tengas pendientes.',
            style: const TextStyle(
                fontSize: 12.5, color: Colors.black54, height: 1.35),
          ),
        ],
      ),
    );
  }

  /// (22-sep) ¿La está recursando ya? Cambia el texto del botón bloqueado.
  bool _estaRecursando(Map<String, dynamic> m) {
    final k = _keyMateria(
        (m['clave'] ?? '').toString(), (m['materia'] ?? '').toString());
    for (final s in _solicitudes) {
      final estado = (s['estado'] ?? '').toString().toLowerCase();
      if (estado.contains('matricul') &&
          _keyMateria((s['clave'] ?? '').toString(),
                  (s['materia'] ?? '').toString()) == k) {
        return true;
      }
    }
    return false;
  }

  Widget _tarjetaReprobada(Map<String, dynamic> m, bool yaPendiente) {
    final materia = (m['materia'] ?? '').toString();
    // (22-sep) Requisito: al corriente en pagos. La tarjeta de arriba lo
    // decía, pero el botón dejaba enviar igual.
    // (5-oct-2026) También se bloquea al llegar al máximo de recursamientos simultáneos (pedir aviso sigue disponible).
    final bloqueadoPorPagos = (_costo != null && _costo!['puedeSolicitar'] == false) || _enCurso['alcanzado'] == true;
    final clave = (m['clave'] ?? '').toString();
    final calif = m['calificacion'];
    final ofertada = m['ofertada'] == true;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(materia,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                      if (clave.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text('Clave: $clave',
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.black45)),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: cessumRed.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    calif != null ? 'Calif. $calif' : 'No acreditada',
                    style: const TextStyle(
                        fontSize: 12,
                        color: cessumRed,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            // (24-sep) Opciones agendadas con sus fechas y su cierre.
            ..._opcionesDe(m, yaPendiente, bloqueadoPorPagos),
            const SizedBox(height: 10),
            if (yaPendiente || !ofertada)
            SizedBox(
              width: double.infinity,
              child: yaPendiente
                  ? OutlinedButton.icon(
                      onPressed: null,
                      icon: Icon(
                          _estaRecursando(m) ? Icons.school : Icons.hourglass_top,
                          size: 18),
                      label: Text(_estaRecursando(m)
                          ? 'La estás recursando'
                          : 'Solicitud en revisión'),
                    )
                  : OutlinedButton.icon(
                      onPressed: () => _solicitar(m),
                      icon: const Icon(Icons.notifications_active_outlined, size: 18),
                      label: const Text('Avísame cuando se oferte'),
                    ),
            ),
            // (24-sep) Una materia autogestiva en todo el programa, solo de una reprobada.
            if (!yaPendiente && calif != null && _autogUsado == null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    onPressed: bloqueadoPorPagos ? null : () => _solicitarAutogestiva(m),
                    icon: const Icon(Icons.self_improvement, size: 18),
                    label: const Text('Solicitar en modalidad autogestiva'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Tarjeta resumen. El detalle completo vive en su propia pantalla: aquí
  /// solo se dice en qué va y qué falta, y se entra con un toque.
  Widget _tarjetaSolicitud(Map<String, dynamic> s) {
    final materia = (s['materia'] ?? '').toString();
    final fecha = (s['fecha'] ?? '').toString();
    final estado = (s['estado'] ?? '').toString();
    final eN = estado.toLowerCase();
    final costo = (s['costo'] as num?)?.toInt() ?? 0;
    final comprobante = (s['comprobante'] ?? '').toString();
    final pagado = s['pagoVerificado'] == true;

    Color color;
    IconData icono;
    if (eN == 'atendida' || eN == 'programada') {
      color = const Color(0xFF1E7D32);
      icono = Icons.check_circle;
    } else if (eN == 'rechazada') {
      color = cessumRed;
      icono = Icons.cancel;
    } else {
      color = cessumGold;
      icono = Icons.hourglass_top;
    }

    // La línea que le dice qué sigue, en una frase.
    String siguiente;
    if (eN == 'rechazada') {
      siguiente = 'Solicitud no procedente · toca para ver el motivo';
    } else if (pagado) {
      siguiente = 'Pago verificado';
    } else if (comprobante.isNotEmpty) {
      siguiente = 'Comprobante en revisión';
    } else if (debePagarRecurso(s)) {
      siguiente = costo > 0 ? 'Falta subir tu comprobante de pago (\$$costo)' : 'Falta subir tu comprobante de pago';
    } else {
      siguiente = 'En revisión de Vicerrectoría';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _abrirDetalle(s),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icono, color: color, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(materia,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                    if (fecha.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(fecha,
                            style: const TextStyle(
                                fontSize: 11, color: Colors.black45)),
                      ),
                    // (5-oct-2026) El botón está aquí, a la vista, no escondido en el detalle.
                    if (debePagarRecurso(s))
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: cessumRed, minimumSize: const Size(0, 36)),
                          onPressed: _subiendo.contains('${s['id']}') ? null : () => _subirDesdeLista(s),
                          icon: _subiendo.contains('${s['id']}')
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.upload_file, size: 17),
                          label: Text(_subiendo.contains('${s['id']}') ? 'Subiendo…' : 'Subir comprobante de pago', style: const TextStyle(fontSize: 12.5)),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Text(siguiente,
                          style: TextStyle(
                              fontSize: 12,
                              height: 1.35,
                              fontWeight: FontWeight.w600,
                              color: pagado
                                  ? const Color(0xFF1E7B34)
                                  : (eN == 'rechazada'
                                      ? cessumRed
                                      : const Color(0xFFB07D12)))),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      estado.isEmpty ? 'Pendiente' : estado,
                      style: TextStyle(
                          fontSize: 11.5,
                          color: color,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Icon(Icons.chevron_right,
                      size: 20, color: Colors.black26),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// (22-sep) SOLICITAR OTRA MATERIA DEL PLAN.
  /// La reprobada se sugiere, pero no es la única que se puede pedir: cada
  /// solicitud la valora Vicerrectoría en el panel.
  Widget _tarjetaOtraMateria() {
    if (_plan.isEmpty) return const SizedBox.shrink();
    final bloqueadoPorPagos =
        _costo != null && _costo!['puedeSolicitar'] == false;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cessumGold.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cessumGold.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: const [
            Icon(Icons.playlist_add, color: cessumGold, size: 20),
            SizedBox(width: 8),
            Expanded(
              child: Text('¿Necesitas recursar otra materia?',
                  style: TextStyle(
                      fontSize: 14.5, fontWeight: FontWeight.bold)),
            ),
          ]),
          const SizedBox(height: 6),
          const Text(
            'Puedes pedir el recursamiento de cualquier materia de tu plan de '
            'estudios, aunque no aparezca como reprobada. Al solicitarla '
            'quedas registrado, y cuando se abra el grupo se te avisa.',
            style: TextStyle(fontSize: 12.5, height: 1.4),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: cessumRed,
                side: const BorderSide(color: cessumRed),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              // El mismo requisito que las demás: con pagos pendientes el
              // Guardián no acepta la solicitud, así que no se ofrece.
              onPressed: bloqueadoPorPagos ? null : _elegirMateriaDelPlan,
              icon: const Icon(Icons.search, size: 18),
              label: Text(bloqueadoPorPagos
                  ? 'Ponte al corriente para solicitar'
                  : 'Elegir materia de mi plan'),
            ),
          ),
        ],
      ),
    );
  }

  /// Selector con buscador: las reprobadas primero, luego las que le faltan
  /// y al final las aprobadas. Lo ya solicitado no se puede volver a pedir.
  Future<void> _elegirMateriaDelPlan() async {
    final pendientes = _pendientesSet();
    final repro = <String, Map<String, dynamic>>{};
    for (final r in _reprobadas) {
      repro[_keyMateria((r['clave'] ?? '').toString(),
          (r['materia'] ?? '').toString())] = r;
    }
    int rango(Map<String, dynamic> m) {
      final k = _keyMateria(
          (m['clave'] ?? '').toString(), (m['materia'] ?? '').toString());
      if (repro.containsKey(k)) return 0;
      return (m['estado'] ?? '').toString().toLowerCase() == 'aprobada' ? 2 : 1;
    }

    final lista = [..._plan];
    lista.sort((x, y) {
      final r = rango(x).compareTo(rango(y));
      if (r != 0) return r;
      return (x['materia'] ?? '')
          .toString()
          .compareTo((y['materia'] ?? '').toString());
    });

    final elegida = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) {
        var filtro = '';
        return StatefulBuilder(builder: (ctx2, setD) {
          final visibles = lista.where((m) {
            if (filtro.isEmpty) return true;
            final f = filtro.toLowerCase();
            return (m['materia'] ?? '').toString().toLowerCase().contains(f) ||
                (m['clave'] ?? '').toString().toLowerCase().contains(f) ||
                (m['ciclo'] ?? '').toString().toLowerCase().contains(f);
          }).toList();
          return AlertDialog(
            title: const Text('Materias de tu plan',
                style: TextStyle(fontSize: 16)),
            content: SizedBox(
              width: 460,
              height: 460,
              child: Column(
                children: [
                  TextField(
                    autofocus: true,
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: const Icon(Icons.search),
                      hintText: 'Busca por nombre, clave o ciclo',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    onChanged: (v) => setD(() => filtro = v),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: visibles.isEmpty
                        ? const Center(
                            child: Text('Ninguna materia coincide.',
                                style: TextStyle(fontSize: 13)))
                        : ListView.builder(
                            itemCount: visibles.length,
                            itemBuilder: (_, i) {
                              final m = visibles[i];
                              final k = _keyMateria(
                                  (m['clave'] ?? '').toString(),
                                  (m['materia'] ?? '').toString());
                              final r = repro[k];
                              final yaPedida = pendientes.contains(k);
                              final cal = (r?['calificacion'] ?? m['cal'] ?? '')
                                  .toString();
                              final etiqueta = r != null
                                  ? 'Reprobada${cal.isNotEmpty ? ' · $cal' : ''}'
                                  : ((m['estado'] ?? '').toString().toLowerCase() ==
                                          'aprobada'
                                      ? 'Aprobada${cal.isNotEmpty ? ' · $cal' : ''}'
                                      : 'Te falta cursarla');
                              final color = r != null
                                  ? cessumRed
                                  : ((m['estado'] ?? '')
                                              .toString()
                                              .toLowerCase() ==
                                          'aprobada'
                                      ? Colors.green.shade700
                                      : cessumGold);
                              return ListTile(
                                dense: true,
                                enabled: !yaPedida,
                                title: Text((m['materia'] ?? '').toString(),
                                    style: const TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600)),
                                subtitle: Text(
                                    [
                                      if ((m['ciclo'] ?? '')
                                          .toString()
                                          .isNotEmpty)
                                        (m['ciclo'] ?? '').toString(),
                                      yaPedida ? 'Ya la solicitaste' : etiqueta,
                                    ].join(' · '),
                                    style: TextStyle(
                                        fontSize: 11.5,
                                        color: yaPedida
                                            ? Theme.of(ctx2).hintColor
                                            : color,
                                        fontWeight: FontWeight.w600)),
                                trailing: yaPedida
                                    ? const Icon(Icons.check, size: 18)
                                    : const Icon(Icons.chevron_right, size: 18),
                                onTap: yaPedida
                                    ? null
                                    : () => Navigator.pop(ctx2, {
                                          ...m,
                                          if (r != null)
                                            'calificacion': r['calificacion'],
                                        }),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx2),
                child: const Text('Cancelar'),
              ),
            ],
          );
        });
      },
    );
    if (elegida != null) await _solicitar(elegida);
  }

  Widget _tarjetaVacia({required IconData icon, required String texto}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        children: [
          Icon(icon, size: 34, color: Colors.black26),
          const SizedBox(height: 8),
          Text(texto,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Colors.black54)),
        ],
      ),
    );
  }
}

/* =====================================================================
 *  DETALLE DE UNA SOLICITUD DE RECURSAMIENTO
 *  ---------------------------------------------------------------------
 *  Es lo que sigue de "Solicitar". Reúne en una sola pantalla las cuatro
 *  cosas que el alumno necesita y que antes estaban repartidas entre una
 *  etiqueta de color y una llamada telefónica:
 *
 *    1. El detalle de la materia (cuál, con qué clave, con qué calificación)
 *    2. El avance del trámite, paso por paso, con lo que falta
 *    3. Los detalles del pago (cuánto, por qué, a quién preguntarle)
 *    4. La carga del comprobante
 *
 *  Se relee del backend después de subir, para que el alumno vea el cambio
 *  de estado sin salir y volver a entrar.
 * ===================================================================== */
class DetalleRecursamientoScreen extends StatefulWidget {
  final Map<String, dynamic> solicitud;
  final Map<String, dynamic>? costo;
  final String matricula;
  final String correo;

  const DetalleRecursamientoScreen({
    super.key,
    required this.solicitud,
    required this.matricula,
    this.costo,
    this.correo = '',
  });

  @override
  State<DetalleRecursamientoScreen> createState() =>
      _DetalleRecursamientoScreenState();
}

class _DetalleRecursamientoScreenState
    extends State<DetalleRecursamientoScreen> {
  late Map<String, dynamic> _s;
  bool _ocupado = false;

  @override
  void initState() {
    super.initState();
    _s = Map<String, dynamic>.from(widget.solicitud);
  }

  String get _id => (_s['id'] ?? '').toString();
  String get _estado => (_s['estado'] ?? '').toString();
  String get _estadoN => _estado.toLowerCase();
  bool get _rechazada => _estadoN == 'rechazada';
  bool get _resuelta => _estadoN == 'atendida' || _estadoN == 'programada';
  bool get _pagado => _s['pagoVerificado'] == true;
  String get _comprobante => (_s['comprobante'] ?? '').toString();
  String get _grupo => (_s['grupoAsignado'] ?? '').toString();
  int get _costo => (_s['costo'] as num?)?.toInt() ?? 0;

  /// Vuelve a pedir la solicitud al backend y refresca solo esta.
  Future<void> _recargar() async {
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'recursamientos_alumno',
        'matricula': widget.matricula,
        'correo': widget.correo,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted || data['ok'] != true) return;
      for (final e in (data['solicitudes'] as List<dynamic>? ?? [])) {
        final m = Map<String, dynamic>.from(e as Map);
        if ((m['id'] ?? '').toString() == _id) {
          setState(() => _s = m);
          return;
        }
      }
    } catch (_) {
      // Si falla la relectura no se pierde nada: se conserva lo que ya se
      // tenía en pantalla. Vaciarla por un error de red sería peor.
    }
  }

  Future<void> _subirComprobante() async {
    if (_id.isEmpty) {
      _aviso('Esta solicitud no tiene folio. Repórtalo a Vicerrectoría.', true);
      return;
    }
    try {
      // (5-oct-2026) La misma función que usa la lista.
      setState(() => _ocupado = true);
      final d = await subirComprobanteRecursamiento(_id);
      if (!mounted) return;
      if (d == null) { setState(() => _ocupado = false); return; }
      setState(() => _ocupado = false);
      _aviso('${d['nota'] ?? d['error'] ?? ''}', d['ok'] != true);
      if (d['ok'] == true) await _recargar();
    } catch (e) {
      if (!mounted) return;
      setState(() => _ocupado = false);
      _aviso('$e', true);
    }
  }

  void _aviso(String msg, bool malo) {
    if (!mounted || msg.trim().isEmpty) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: malo ? cessumRed : const Color(0xFF1E7B34),
      content: Text(msg),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Detalle del recursamiento'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
            onPressed: _ocupado ? null : _recargar,
          ),
        ],
      ),
      body: RefreshIndicator(
        color: cessumRed,
        onRefresh: _recargar,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // (5-oct-2026) Si falta el pago, es lo primero que ve.
            if (debePagarRecurso(_s)) ...[_bloquePago(), const SizedBox(height: 16)],
            _bloqueMateria(),
            const SizedBox(height: 16),
            _bloqueAvance(),
            const SizedBox(height: 16),
            if (!debePagarRecurso(_s)) ...[_bloquePago(), const SizedBox(height: 16)],
            _bloqueAyuda(),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  // ---------- 1. LA MATERIA ----------
  Widget _bloqueMateria() {
    final materia = (_s['materia'] ?? '').toString();
    final clave = (_s['clave'] ?? '').toString();
    final programa = (_s['programa'] ?? '').toString();
    final generacion = (_s['generacion'] ?? '').toString();
    final calif = _s['calificacion'];
    final fecha = (_s['fecha'] ?? '').toString();
    final comentario = (_s['comentario'] ?? '').toString();

    return _tarjeta(
      icono: Icons.menu_book,
      titulo: 'La materia',
      hijos: [
        Text(materia,
            style: const TextStyle(
                fontSize: 17, fontWeight: FontWeight.w700, height: 1.25)),
        const SizedBox(height: 8),
        if (clave.isNotEmpty) _dato('Clave', clave),
        if (programa.isNotEmpty) _dato('Programa', programa),
        if (generacion.isNotEmpty) _dato('Generación', generacion),
        if (calif != null && calif.toString().isNotEmpty)
          _dato('Calificación previa', '$calif'),
        if (fecha.isNotEmpty) _dato('Solicitado el', fecha),
        if (_id.isNotEmpty) _dato('Folio', _id),
        if (comentario.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text('Tu comentario: $comentario',
                style: const TextStyle(
                    fontSize: 12.5, height: 1.4, color: Colors.black54)),
          ),
        ],
      ],
    );
  }

  // ---------- 2. EL AVANCE ----------
  Widget _bloqueAvance() {
    // Cada paso: hecho / en curso / pendiente. El alumno debe poder señalar
    // con el dedo en qué renglón está parado su trámite.
    final pasos = <List<dynamic>>[];

    pasos.add([
      'Solicitud enviada',
      'Vicerrectoría ya la recibió.',
      2, // 2 = hecho
    ]);

    if (_rechazada) {
      pasos.add([
        'Solicitud no procedente',
        (_s['notas'] ?? '').toString().isNotEmpty
            ? (_s['notas'] ?? '').toString()
            : 'Vicerrectoría no autorizó este recursamiento.',
        3, // 3 = detenido
      ]);
    } else {
      pasos.add([
        'Revisión de Vicerrectoría',
        _resuelta
            ? 'Autorizada.'
            : 'En revisión. Te contactarán para acordar los detalles.',
        _resuelta ? 2 : 1,
      ]);

      pasos.add([
        'Pago del recursamiento',
        _pagado
            ? 'Pago verificado.'
            : (_comprobante.isNotEmpty
                ? 'Comprobante recibido, en revisión de Vicerrectoría.'
                : 'Falta que subas tu comprobante de pago.'),
        _pagado ? 2 : (_comprobante.isNotEmpty ? 1 : 0),
      ]);

      pasos.add([
        'Grupo asignado',
        _grupo.isNotEmpty
            ? 'Quedaste en: $_grupo'
            : 'Se te asigna un grupo cuando el pago quede verificado.',
        _grupo.isNotEmpty ? 2 : 0,
      ]);

      pasos.add([
        'Listo para cursar',
        (_pagado && _grupo.isNotEmpty)
            ? 'Ya puedes entrar al Aula con tu grupo.'
            : 'Al completar los pasos anteriores.',
        (_pagado && _grupo.isNotEmpty) ? 2 : 0,
      ]);
    }

    return _tarjeta(
      icono: Icons.timeline,
      titulo: 'Avance de tu trámite',
      hijos: [
        for (var i = 0; i < pasos.length; i++)
          _paso(
            titulo: pasos[i][0] as String,
            detalle: pasos[i][1] as String,
            estado: pasos[i][2] as int,
            ultimo: i == pasos.length - 1,
          ),
      ],
    );
  }

  Widget _paso({
    required String titulo,
    required String detalle,
    required int estado, // 0 pendiente · 1 en curso · 2 hecho · 3 detenido
    required bool ultimo,
  }) {
    Color c;
    IconData ic;
    switch (estado) {
      case 2:
        c = const Color(0xFF1E7B34);
        ic = Icons.check_circle;
        break;
      case 1:
        c = const Color(0xFFB07D12);
        ic = Icons.radio_button_checked;
        break;
      case 3:
        c = cessumRed;
        ic = Icons.cancel;
        break;
      default:
        c = Colors.black26;
        ic = Icons.radio_button_unchecked;
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Icon(ic, size: 20, color: c),
              if (!ultimo)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    color: estado == 2
                        ? const Color(0xFF1E7B34).withValues(alpha: .35)
                        : Colors.black12,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: ultimo ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo,
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: estado == 0 ? Colors.black45 : Colors.black87)),
                  const SizedBox(height: 2),
                  Text(detalle,
                      style: const TextStyle(
                          fontSize: 12.5, height: 1.4, color: Colors.black54)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- 3. EL PAGO ----------
  Widget _bloquePago() {
    if (_rechazada) {
      return _tarjeta(
        icono: Icons.info_outline,
        titulo: 'Pago',
        hijos: const [
          Text(
            'Esta solicitud no procedió, así que no hay nada que pagar. Si '
            'crees que se trata de un error, comunícate con Vicerrectoría '
            'antes de hacer cualquier depósito.',
            style: TextStyle(fontSize: 13, height: 1.45),
          ),
        ],
      );
    }

    final comoSeCalcula = (widget.costo?['comoSeCalcula'] ?? '').toString();

    return _tarjeta(
      icono: Icons.receipt_long,
      titulo: 'Tu pago',
      hijos: [
        if (_costo > 0) ...[
          Text('COSTO DE ESTE RECURSAMIENTO',
              style: TextStyle(
                  fontSize: 9.5,
                  letterSpacing: .9,
                  fontWeight: FontWeight.w800,
                  color: cessumGold)),
          Text('\$$_costo',
              style: const TextStyle(
                  fontSize: 32, fontWeight: FontWeight.w800, height: 1.15)),
          const SizedBox(height: 4),
          // El costo se congela al solicitar: si el plan sube después, a
          // quien ya solicitó se le respeta lo que se le dijo.
          const Text(
            'Este es el monto que se te congeló al solicitar. Aunque el plan '
            'de pagos cambie después, a ti se te respeta esta cantidad.',
            style: TextStyle(fontSize: 12.5, height: 1.45, color: Colors.black54),
          ),
          if (comoSeCalcula.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(comoSeCalcula,
                style: const TextStyle(fontSize: 12.5, height: 1.45)),
          ],
        ] else ...[
          const Text(
            'El costo no quedó registrado en tu solicitud. Es la mitad de la colegiatura de lista de tu programa, '
            'sin beca. Confírmalo al 642 130 5193 y, en cuanto pagues, sube aquí tu comprobante.',
            style: TextStyle(fontSize: 13, height: 1.45),
          ),
        ],
        const SizedBox(height: 14),
        _estadoDelComprobante(),
      ],
    );
  }

  Widget _estadoDelComprobante() {
    if (_pagado) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: const Color(0xFF1E7B34).withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: const Color(0xFF1E7B34).withValues(alpha: 0.35)),
        ),
        child: Row(children: [
          const Icon(Icons.verified, size: 20, color: Color(0xFF1E7B34)),
          const SizedBox(width: 9),
          const Expanded(
            child: Text(
              'Pago verificado por Vicerrectoría. No tienes que hacer nada más '
              'por este concepto.',
              style: TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E7B34)),
            ),
          ),
        ]),
      );
    }

    if (_comprobante.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: cessumGold.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: cessumGold.withValues(alpha: 0.45)),
            ),
            child: Row(children: const [
              Icon(Icons.hourglass_top, size: 20, color: Color(0xFFB07D12)),
              SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Comprobante recibido. Vicerrectoría lo está revisando y te '
                  'confirma en cuanto quede verificado.',
                  style: TextStyle(fontSize: 12.5, height: 1.4),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.black54,
                    minimumSize: const Size(0, 38)),
                onPressed: () => html.window.open(_comprobante, '_blank'),
                icon: const Icon(Icons.visibility, size: 16),
                label: const Text('Ver el que subí',
                    style: TextStyle(fontSize: 12.5)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                    foregroundColor: cessumGold,
                    side: BorderSide(color: cessumGold.withValues(alpha: .5)),
                    minimumSize: const Size(0, 38)),
                onPressed: _ocupado ? null : _subirComprobante,
                icon: const Icon(Icons.autorenew, size: 16),
                label: const Text('Reemplazar',
                    style: TextStyle(fontSize: 12.5)),
              ),
            ),
          ]),
        ],
      );
    }

    // Todavía no sube nada: este es el único paso que depende de él.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Text(
            'Sube tu comprobante de depósito o transferencia. Se acepta PDF o '
            'foto, y debe verse la fecha y el monto. En cuanto lo subas, '
            'Vicerrectoría recibe el aviso automáticamente.',
            style: TextStyle(fontSize: 12.5, height: 1.45, color: Colors.black54),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: cessumRed,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 46),
            ),
            onPressed: _ocupado ? null : _subirComprobante,
            icon: _ocupado
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.upload_file, size: 19),
            label: Text(_ocupado ? 'Subiendo…' : 'Subir comprobante de pago'),
          ),
        ),
      ],
    );
  }

  // ---------- 4. AYUDA ----------
  Widget _bloqueAyuda() {
    final dudas = (widget.costo?['dudas'] ?? '').toString();
    final notas = (_s['notas'] ?? '').toString();
    return _tarjeta(
      icono: Icons.support_agent,
      titulo: '¿Dudas?',
      hijos: [
        if (notas.isNotEmpty && !_rechazada) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: cessumGold.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text('Nota de Vicerrectoría: $notas',
                style: const TextStyle(fontSize: 12.5, height: 1.45)),
          ),
          const SizedBox(height: 10),
        ],
        Text(
          dudas.isNotEmpty
              ? dudas
              : 'Dudas sobre el costo o el pago: 642 130 5193',
          style: const TextStyle(fontSize: 13, height: 1.45),
        ),
      ],
    );
  }

  // ---------- piezas ----------
  Widget _tarjeta({
    required IconData icono,
    required String titulo,
    required List<Widget> hijos,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: Colors.black12),
      ),
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icono, size: 18, color: cessumRed),
            const SizedBox(width: 8),
            Text(titulo,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: cessumRed)),
          ]),
          const SizedBox(height: 12),
          ...hijos,
        ],
      ),
    );
  }

  Widget _dato(String etiqueta, String valor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 118,
            child: Text(etiqueta,
                style: const TextStyle(fontSize: 12.5, color: Colors.black45)),
          ),
          Expanded(
            child: Text(valor,
                style: const TextStyle(
                    fontSize: 12.5, height: 1.35, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

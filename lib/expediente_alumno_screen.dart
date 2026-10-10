import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';
import 'alumnos_service.dart';

// =====================================================================
// PANTALLA: "Expediente 360 del alumno" (lado del ADMINISTRADOR)
// ---------------------------------------------------------------------
// Busca por matricula y muestra, en un solo lugar, todo lo que el
// sistema sabe del alumno: datos, vigencia, calificaciones (validadas e
// historial), credencial, tramites y adeudo.
//
// CONTRATO CON EL GUARDIAN (debe coincidir con Code.gs):
//   expediente_alumno (GET, parametro: matricula)
//     -> { ok, encontrado,
//          alumno: { matricula, nombre, programa, generacion, correo },
//          vigencia: { vigente, motivo },
//          calificaciones: { promedio, validadas, enValidacion,
//                            materiasValidadas:[{clave,materia,cal,letra,ciclo}],
//                            historial:[{materia,ciclo,calificacion,enLetra,estatus}] },
//          credencial: { estado, curp, observaciones, pdfUrl, fotoUrl },
//          tramites: [{ fecha, estatus, tipo, observaciones, documento }],
//          adeudo: { alCorriente, pendientes:[{concepto}] } }
// =====================================================================

const Color _hueso = Color(0xFFF5F1E8);

class ExpedienteAlumnoScreen extends StatefulWidget {
  const ExpedienteAlumnoScreen({super.key});

  @override
  State<ExpedienteAlumnoScreen> createState() => _ExpedienteAlumnoScreenState();
}

class _ExpedienteAlumnoScreenState extends State<ExpedienteAlumnoScreen> {
  final TextEditingController _ctrl = TextEditingController();
  bool _cargando = false;
  String? _error;
  Map<String, dynamic>? _exp;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _buscar() async {
    final mat = _ctrl.text.trim();
    if (mat.isEmpty) {
      _aviso('Escribe una matricula.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _cargando = true;
      _error = null;
      _exp = null;
    });
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'expediente_alumno',
        'matricula': mat,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) {
        throw Exception(data['error'] ?? 'Respuesta invalida');
      }
      if (!mounted) return;
      setState(() {
        _exp = data;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo cargar el expediente. Revisa la matricula '
            'y tu conexion.';
      });
    }
  }

  void _aviso(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _abrir(String url) async {
    if (url.isEmpty) return;
    try {
      await launchUrl(Uri.parse(url), webOnlyWindowName: '_blank');
    } catch (_) {
      _aviso('No se pudo abrir el enlace.');
    }
  }

  // V1083: el backend exige sesion administrativa, programa y corte exacto.
  // El periodo que muestra el historial curricular NO es necesariamente
  // el periodo de la hoja Calificaciones: se solicita expresamente.
  bool _reenviando = false;
  bool _reenvioBloqueado = false;

  Future<void> _reenviarBoleta(
      String matricula, String nombre, String programaInicial) async {
    if (_reenviando || _reenvioBloqueado || matricula.trim().isEmpty) return;
    final historial = ((_exp?['calificaciones'] as Map?)?['historial'] as List?) ?? [];
    final programas = <String>{};
    if (programaInicial.trim().isNotEmpty) programas.add(programaInicial.trim());
    for (final item in historial) {
      if (item is! Map) continue;
      final programa = (item['programa'] ?? '').toString().trim();
      if (programa.isNotEmpty) programas.add(programa);
    }
    final opciones = programas.toList()..sort();
    String? programaSeleccionado = opciones.length == 1 ? opciones.first : null;
    final cicloCtrl = TextEditingController();
    final periodoCtrl = TextEditingController();
    final seleccion = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, actualizar) => AlertDialog(
          title: const Text('Elegir corte de la boleta'),
          content: SizedBox(
            width: 450,
            child: SingleChildScrollView(
              child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$nombre · Matrícula $matricula',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                const Text('Elige un programa y escribe exactamente el ciclo '
                    'y el periodo registrados en el acta validada. No se '
                    'reenviará el historial completo.'),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: programaSeleccionado,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Programa académico', border: OutlineInputBorder(),
                  ),
                  items: opciones.map((p) => DropdownMenuItem(
                    value: p, child: Text(p, overflow: TextOverflow.ellipsis),
                  )).toList(),
                  onChanged: (v) => actualizar(() => programaSeleccionado = v),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: cicloCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Ciclo exacto del acta',
                    hintText: 'Tal como aparece en Calificaciones',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: periodoCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Periodo exacto del acta',
                    hintText: 'No inferirlo del periodo curricular',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar')),
            FilledButton(
              onPressed: () {
                if ((programaSeleccionado ?? '').trim().isEmpty ||
                    cicloCtrl.text.trim().isEmpty || periodoCtrl.text.trim().isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                    content: Text('Programa, ciclo y periodo son obligatorios.'),
                  ));
                  return;
                }
                Navigator.pop(ctx, {
                  'programa': programaSeleccionado!.trim(),
                  'ciclo': cicloCtrl.text.trim(),
                  'periodo': periodoCtrl.text.trim(),
                });
              },
              child: const Text('Consultar vista previa'),
            ),
          ],
        ),
      ),
    );
    cicloCtrl.dispose();
    periodoCtrl.dispose();
    if (!mounted || seleccion == null) return;

    setState(() => _reenviando = true);
    try {
      final solicitante = await SessionStore.realEmail() ?? '';
      if (solicitante.trim().isEmpty) {
        throw Exception('Inicia sesión administrativa para continuar.');
      }
      final payload = <String, String>{
        'accion': 'reenviar_boleta',
        'solicitante': solicitante,
        'matricula': matricula,
        'programa': seleccion['programa']!,
        'ciclo': seleccion['ciclo']!,
        'periodo': seleccion['periodo']!,
      };
      // No se manda un correo personalizado: el servidor utiliza el correo
      // académico que consta en Calificaciones y lo devuelve en la vista previa.
      Future<Map<String, dynamic>> solicitar(Map<String, String> datos) async {
        final respuesta = await http.post(
          Uri.parse(guardianUrl),
          headers: {'Content-Type': 'text/plain;charset=utf-8'},
          body: jsonEncode(datos),
        ).timeout(const Duration(seconds: 90));
        if (respuesta.statusCode != 200) {
          throw Exception('HTTP ${respuesta.statusCode}: no se confirmó el resultado.');
        }
        final body = jsonDecode(respuesta.body);
        if (body is! Map) throw const FormatException('Respuesta no válida');
        return Map<String, dynamic>.from(body);
      }

      final vista = await solicitar(payload); // Sin confirmar: nunca envía.
      if (!mounted) return;
      if (vista['ok'] != true || vista['previa'] != true) {
        throw Exception((vista['error'] ?? 'No se obtuvo vista previa segura.').toString());
      }
      final materias = (vista['materias'] as num?)?.toInt() ?? 0;
      final destino = (vista['destino'] ?? '').toString();
      if (materias <= 0 || !destino.contains('@')) {
        throw Exception('La vista previa no identifica materias o destinatario.');
      }
      final confirmado = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Confirmar reenvío puntual'),
          content: Text('Alumno: $nombre\nMatrícula: $matricula\n'
              'Programa: ${seleccion['programa']}\nCiclo: ${seleccion['ciclo']}\n'
              'Periodo: ${seleccion['periodo']}\n'
              'Materias: $materias\nDestino: $destino\n\n'
              'Solo se reenviará este corte. Si falla la conexión, NO pulses '
              'otra vez: verifica primero el registro administrativo.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: cessumRed),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Confirmar reenvío'),
            ),
          ],
        ),
      );
      if (confirmado != true || !mounted) return;
      // Una vez confirmada la operación, impedir repeticiones en esta pantalla.
      _reenvioBloqueado = true;
      final res = await solicitar({...payload, 'confirmar': 'ENVIAR'});
      if (!mounted) return;
      if (res['ok'] == true && res['previa'] != true) {
        _aviso('Reenvío registrado para $destino ($materias materia(s)).');
      } else {
        throw Exception((res['error'] ?? res['nota'] ??
            'Resultado no confirmado. Conciliar antes de intentar nuevamente.').toString());
      }
    } catch (e) {
      if (mounted) _aviso('Reenvío no confirmado: $e. Verifica el estado antes de repetir.');
    } finally {
      if (mounted) setState(() => _reenviando = false);
    }
  }

  Future<void> _buscarPorNombre() async {
    List<AlumnoInfo> todos;
    try {
      todos = await AlumnosService.listarAlumnos();
    } catch (e) {
      _aviso('No se pudo cargar el padrón ($e).');
      return;
    }
    if (!mounted) return;
    final seleccion = await showDialog<AlumnoInfo>(
      context: context,
      builder: (ctx) {
        String q = '';
        return StatefulBuilder(
          builder: (ctx, setSt) {
            final filtro = q.trim().toLowerCase();
            final lista = filtro.isEmpty
                ? <AlumnoInfo>[]
                : todos
                    .where((a) => a.nombre.toLowerCase().contains(filtro))
                    .take(40)
                    .toList();
            return AlertDialog(
              title: const Text('Buscar por nombre'),
              content: SizedBox(
                width: 440,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      autofocus: true,
                      onChanged: (v) => setSt(() => q = v),
                      decoration: const InputDecoration(
                        hintText: 'Escribe el nombre del alumno',
                        isDense: true,
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 300,
                      width: 440,
                      child: filtro.isEmpty
                          ? const Center(
                              child: Text('Escribe para buscar...',
                                  style: TextStyle(color: Colors.black45)))
                          : lista.isEmpty
                              ? const Center(
                                  child: Text('Sin coincidencias.',
                                      style:
                                          TextStyle(color: Colors.black45)))
                              : ListView.builder(
                                  itemCount: lista.length,
                                  itemBuilder: (c, i) {
                                    final a = lista[i];
                                    return ListTile(
                                      dense: true,
                                      title: Text(a.nombre,
                                          style: const TextStyle(
                                              fontSize: 13.5)),
                                      subtitle: Text(
                                          '${a.matricula} · ${a.programa}',
                                          style:
                                              const TextStyle(fontSize: 11.5)),
                                      onTap: () => Navigator.pop(ctx, a),
                                    );
                                  },
                                ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cerrar')),
              ],
            );
          },
        );
      },
    );
    if (seleccion != null) {
      _ctrl.text = seleccion.matricula;
      _buscar();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Expediente del alumno'),
      ),
      body: Column(
        children: [
          _barraBusqueda(),
          Expanded(child: _cuerpo()),
        ],
      ),
    );
  }

  Widget _barraBusqueda() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _ctrl,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _buscar(),
              decoration: InputDecoration(
                labelText: 'Matricula',
                hintText: 'p. ej. 26M0123',
                prefixIcon: const Icon(Icons.badge_outlined),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton.icon(
            onPressed: _cargando ? null : _buscar,
            icon: const Icon(Icons.search),
            label: const Text('Buscar'),
            style: ElevatedButton.styleFrom(
              backgroundColor: cessumRed,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _cargando ? null : _buscarPorNombre,
            icon: const Icon(Icons.person_search, color: cessumGold),
            tooltip: 'Buscar por nombre',
            style: IconButton.styleFrom(
              side: const BorderSide(color: cessumGold),
              padding: const EdgeInsets.all(14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cuerpo() {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator(color: cessumRed));
    }
    if (_error != null) {
      return _mensajeCentral(Icons.error_outline, _error!, cessumRed);
    }
    if (_exp == null) {
      return _mensajeCentral(
        Icons.person_search_outlined,
        'Escribe una matricula y presiona Buscar para ver el expediente '
            'completo del alumno.',
        Colors.black45,
      );
    }
    if (_exp!['encontrado'] != true) {
      return _mensajeCentral(
        Icons.search_off,
        'No se encontro ningun alumno con esa matricula.',
        Colors.black45,
      );
    }
    return _expediente();
  }

  Widget _mensajeCentral(IconData icono, String texto, Color color) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, size: 56, color: color),
            const SizedBox(height: 14),
            Text(
              texto,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: color),
            ),
          ],
        ),
      ),
    );
  }

  Widget _expediente() {
    final alumno = (_exp!['alumno'] as Map<String, dynamic>?) ?? {};
    final vig = (_exp!['vigencia'] as Map<String, dynamic>?) ?? {};
    final cal = (_exp!['calificaciones'] as Map<String, dynamic>?) ?? {};
    final cred = (_exp!['credencial'] as Map<String, dynamic>?) ?? {};
    final tramites = (_exp!['tramites'] as List?) ?? [];
    final adeudo = (_exp!['adeudo'] as Map<String, dynamic>?) ?? {};

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
      children: [
        _tarjetaAlumno(alumno, vig),
        _tarjetaCalificaciones(cal),
        _tarjetaCredencial(cred),
        _tarjetaTramites(tramites),
        _tarjetaAdeudo(adeudo),
      ],
    );
  }

  // ----- Tarjeta: datos del alumno + vigencia -----
  Widget _tarjetaAlumno(Map<String, dynamic> a, Map<String, dynamic> vig) {
    final vigente = vig['vigente'] == true;
    final motivo = (vig['motivo'] ?? '').toString();
    return _tarjeta(
      icono: Icons.person,
      titulo: (a['nombre'] ?? 'Alumno').toString(),
      hijos: [
        _campo('Matricula', (a['matricula'] ?? '').toString()),
        _campo('Programa', (a['programa'] ?? '').toString()),
        _campo('Generacion', (a['generacion'] ?? '').toString()),
        _campo('Correo', (a['correo'] ?? '').toString()),
        const SizedBox(height: 8),
        _chip(
          vigente ? 'Vigente (inscrito y activo)' : 'No vigente',
          vigente ? Colors.green.shade700 : cessumRed,
          vigente ? Icons.verified : Icons.cancel,
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: cessumRed,
              side: const BorderSide(color: cessumRed, width: 1.3),
              padding: const EdgeInsets.symmetric(vertical: 11),
            ),
            onPressed: (_reenviando || _reenvioBloqueado) ? null : () => _reenviarBoleta(
              (a['matricula'] ?? '').toString(),
              (a['nombre'] ?? 'Alumno').toString(),
              (a['programa'] ?? '').toString(),
            ),
            icon: const Icon(Icons.forward_to_inbox, size: 19),
            label: const Text('Reenviar boleta'),
          ),
        ),
        if (!vigente && motivo.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(motivo,
                style: const TextStyle(color: Colors.black54, fontSize: 13)),
          ),
      ],
    );
  }

  // ----- Tarjeta: calificaciones -----
  Widget _tarjetaCalificaciones(Map<String, dynamic> cal) {
    final promedio = cal['promedio'];
    final validadas = (cal['validadas'] ?? 0);
    final enVal = (cal['enValidacion'] ?? 0);
    final materias = (cal['materiasValidadas'] as List?) ?? [];
    final historial = (cal['historial'] as List?) ?? [];
    final promTxt = (promedio is num) ? promedio.toStringAsFixed(1) : '-';

    return _tarjeta(
      icono: Icons.school,
      titulo: 'Calificaciones',
      hijos: [
        Row(
          children: [
            _mini('Promedio', promTxt, cessumGold),
            _mini('Validadas', '$validadas', Colors.green.shade700),
            _mini('En validacion', '$enVal', Colors.orange.shade800),
          ],
        ),
        const SizedBox(height: 10),
        if (historial.isEmpty)
          const Text('Sin calificaciones registradas.',
              style: TextStyle(color: Colors.black54))
        else
          ...historial.map((m) {
            final mm = (m as Map).cast<String, dynamic>();
            final est = (mm['estatus'] ?? '').toString();
            final esVal = est.toLowerCase() == 'validada';
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                esVal ? Icons.check_circle : Icons.hourglass_bottom,
                color: esVal ? Colors.green.shade700 : Colors.orange.shade800,
                size: 20,
              ),
              title: Text((mm['materia'] ?? '').toString(),
                  style: const TextStyle(fontSize: 14)),
              subtitle: Text(
                'Ciclo ${mm['ciclo'] ?? ''} · $est',
                style: const TextStyle(fontSize: 12),
              ),
              trailing: Text(
                '${mm['calificacion'] ?? ''}',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16, color: cessumRed),
              ),
            );
          }),
      ],
    );
  }

  // ----- Tarjeta: credencial -----
  Widget _tarjetaCredencial(Map<String, dynamic> c) {
    final estado = (c['estado'] ?? 'NoSolicitada').toString();
    final pdf = (c['pdfUrl'] ?? '').toString();
    final foto = (c['fotoUrl'] ?? '').toString();
    final obs = (c['observaciones'] ?? '').toString();

    Color color;
    IconData icono;
    switch (estado.toLowerCase()) {
      case 'aprobada':
        color = Colors.green.shade700;
        icono = Icons.verified;
        break;
      case 'rechazada':
        color = cessumRed;
        icono = Icons.cancel;
        break;
      case 'observaciones':
        color = Colors.orange.shade800;
        icono = Icons.error_outline;
        break;
      case 'nosolicitada':
        color = Colors.black45;
        icono = Icons.help_outline;
        break;
      default:
        color = Colors.orange.shade800;
        icono = Icons.hourglass_bottom;
    }

    return _tarjeta(
      icono: Icons.badge,
      titulo: 'Credencial',
      hijos: [
        _chip(estado, color, icono),
        if (obs.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Observaciones: $obs',
                style: const TextStyle(color: Colors.black54, fontSize: 13)),
          ),
        if (pdf.isNotEmpty || foto.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 8,
              children: [
                if (pdf.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: () => _abrir(pdf),
                    icon: const Icon(Icons.picture_as_pdf, size: 18),
                    label: const Text('Ver PDF'),
                  ),
                if (foto.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: () => _abrir(foto),
                    icon: const Icon(Icons.photo, size: 18),
                    label: const Text('Ver foto'),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  // ----- Tarjeta: tramites -----
  Widget _tarjetaTramites(List tramites) {
    return _tarjeta(
      icono: Icons.description,
      titulo: 'Tramites (${tramites.length})',
      hijos: [
        if (tramites.isEmpty)
          const Text('Sin tramites registrados.',
              style: TextStyle(color: Colors.black54))
        else
          ...tramites.map((t) {
            final tt = (t as Map).cast<String, dynamic>();
            final doc = (tt['documento'] ?? '').toString();
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.assignment_outlined,
                  color: cessumGold, size: 20),
              title: Text((tt['tipo'] ?? 'Tramite').toString(),
                  style: const TextStyle(fontSize: 14)),
              subtitle: Text(
                '${tt['fecha'] ?? ''} · ${tt['estatus'] ?? ''}',
                style: const TextStyle(fontSize: 12),
              ),
              trailing: doc.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.open_in_new, size: 18),
                      color: cessumRed,
                      onPressed: () => _abrir(doc),
                    )
                  : null,
            );
          }),
      ],
    );
  }

  // ----- Tarjeta: adeudo -----
  Widget _tarjetaAdeudo(Map<String, dynamic> ad) {
    final alCorriente = ad['alCorriente'] == true;
    final pendientes = (ad['pendientes'] as List?) ?? [];
    return _tarjeta(
      icono: Icons.payments,
      titulo: 'Adeudo',
      hijos: [
        _chip(
          alCorriente ? 'Al corriente' : 'Con pendientes',
          alCorriente ? Colors.green.shade700 : Colors.orange.shade800,
          alCorriente ? Icons.check_circle : Icons.warning_amber,
        ),
        if (!alCorriente && pendientes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: pendientes.map((p) {
                final pp = (p as Map).cast<String, dynamic>();
                return Text('• ${pp['concepto'] ?? ''}',
                    style: const TextStyle(color: Colors.black54, fontSize: 13));
              }).toList(),
            ),
          ),
      ],
    );
  }

  // ===================== Widgets auxiliares =====================

  Widget _tarjeta({
    required IconData icono,
    required String titulo,
    required List<Widget> hijos,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icono, color: cessumRed, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    titulo,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const Divider(height: 18),
            ...hijos,
          ],
        ),
      ),
    );
  }

  Widget _campo(String etiqueta, String valor) {
    if (valor.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(etiqueta,
                style: const TextStyle(color: Colors.black54, fontSize: 13)),
          ),
          Expanded(
            child: Text(valor,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  Widget _chip(String texto, Color color, IconData icono) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, size: 16, color: color),
            const SizedBox(width: 6),
            Text(texto,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.w600, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _mini(String etiqueta, String valor, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(valor,
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 2),
            Text(etiqueta,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, color: Colors.black54)),
          ],
        ),
      ),
    );
  }
}

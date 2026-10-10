import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'helpers.dart';
import 'auth/session_store.dart';

/// Caja de herramientas administrativas: utilidades chicas y rapidas.
class HerramientasScreen extends StatefulWidget {
  const HerramientasScreen({super.key});

  @override
  State<HerramientasScreen> createState() => _HerramientasScreenState();
}

class _HerramientasScreenState extends State<HerramientasScreen> {
  bool _procesando = false;
  // Correo de quien usa las herramientas; se firma en cada documento generado
  // para dejar trazabilidad real en la bitácora.
  String _correoActor = '';

  @override
  void initState() {
    super.initState();
    _cargarActor();
  }

  Future<void> _cargarActor() async {
    // (24-sep) Correo REAL: en «Ver como profesor» el de la vista es el del profesor.
    final c = await SessionStore.realEmail();
    if (mounted && c != null) setState(() => _correoActor = c);
  }

  /* ---------------- M2: Constancia de reconocimiento ---------------- */
  Future<void> _reconocimiento() async {
    final nombre = TextEditingController();
    final motivo = TextEditingController();
    final fecha = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Constancia de reconocimiento',
            style: TextStyle(fontSize: 16)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nombre,
                decoration: const InputDecoration(
                  labelText: 'Nombre de quien recibe *',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: motivo,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Motivo *',
                  hintText: 'Ej. Por su destacada participacion en...',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: fecha,
                decoration: const InputDecoration(
                  labelText: 'Fecha/lugar (opcional)',
                  hintText: 'Se pone la fecha de hoy si lo dejas vacio',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () {
              if (nombre.text.trim().isEmpty || motivo.text.trim().isEmpty) {
                return;
              }
              Navigator.pop(ctx, true);
            },
            child: const Text('Generar'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _procesando = true);
    try {
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'reconocimiento_pdf',
                'actor': _correoActor,
                'nombre': nombre.text.trim(),
                'motivo': motivo.text.trim(),
                'fecha': fecha.text.trim(),
              }))
          .timeout(const Duration(seconds: 90));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      final pdf = (data['pdf'] ?? '').toString();
      if (!mounted) return;
      if (pdf.isNotEmpty) Helpers.abrirUrlExterna(pdf, context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        backgroundColor: Colors.green,
        content: Text('Reconocimiento generado.'),
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text('No se pudo: $e'.replaceAll('Exception: ', '')),
        ));
      }
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  /* ---------------- M2: Exportar alumnos a CSV ---------------- */
  Future<void> _exportarCsv() async {
    setState(() => _procesando = true);
    try {
      final resp = await http
          .get(Uri.parse('$guardianUrl?accion=exportar_alumnos_csv'))
          .timeout(const Duration(seconds: 90));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      final csv = (data['csv'] ?? '').toString();
      final filas = (data['filas'] ?? 0);
      if (!mounted) return;
      await _mostrarCsv('Alumnos activos ($filas)', csv);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text('No se pudo: $e'.replaceAll('Exception: ', '')),
        ));
      }
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  /* ---------------- M3: Validador de CURP (local) ---------------- */
  Future<void> _validarCurp() async {
    final curp = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setS) {
          final texto = curp.text.trim().toUpperCase();
          final res = _analizarCurp(texto);
          return AlertDialog(
            title: const Text('Validar CURP', style: TextStyle(fontSize: 16)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: curp,
                  textCapitalization: TextCapitalization.characters,
                  onChanged: (_) => setS(() {}),
                  decoration: const InputDecoration(
                    labelText: 'CURP (18 caracteres)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                if (texto.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: (res['valida'] == true
                              ? const Color(0xFF1E8E3E)
                              : cessumRed)
                          .withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                                res['valida'] == true
                                    ? Icons.check_circle
                                    : Icons.cancel,
                                size: 18,
                                color: res['valida'] == true
                                    ? const Color(0xFF1E8E3E)
                                    : cessumRed),
                            const SizedBox(width: 8),
                            Text(
                                res['valida'] == true
                                    ? 'Formato valido'
                                    : 'Formato no valido',
                                style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                    color: res['valida'] == true
                                        ? const Color(0xFF1E8E3E)
                                        : cessumRed)),
                          ],
                        ),
                        if (res['valida'] == true) ...[
                          const SizedBox(height: 8),
                          Text('Fecha de nacimiento: ${res['fecha']}',
                              style: const TextStyle(fontSize: 12.5)),
                          Text('Sexo: ${res['sexo']}',
                              style: const TextStyle(fontSize: 12.5)),
                          Text('Entidad: ${res['entidad']}',
                              style: const TextStyle(fontSize: 12.5)),
                        ] else ...[
                          const SizedBox(height: 6),
                          Text('${res['motivo']}',
                              style: const TextStyle(
                                  fontSize: 12, color: cessumRed)),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx2),
                  child: const Text('Cerrar')),
            ],
          );
        },
      ),
    );
  }

  Map<String, dynamic> _analizarCurp(String curp) {
    if (curp.isEmpty) return {'valida': false, 'motivo': ''};
    final re = RegExp(r'^[A-Z]{4}\d{6}[HM][A-Z]{5}[0-9A-Z]\d$');
    if (curp.length != 18) {
      return {
        'valida': false,
        'motivo': 'Debe tener 18 caracteres (tiene ${curp.length}).'
      };
    }
    if (!re.hasMatch(curp)) {
      return {
        'valida': false,
        'motivo': 'No cumple el patron oficial de la CURP.'
      };
    }
    final aa = int.tryParse(curp.substring(4, 6)) ?? 0;
    final mm = curp.substring(6, 8);
    final dd = curp.substring(8, 10);
    final h = curp[16];
    final siglo = RegExp(r'\d').hasMatch(h) ? 1900 : 2000;
    final anio = siglo + aa;
    final sexo = curp[10] == 'H' ? 'Hombre' : 'Mujer';
    final entidades = {
      'AS': 'Aguascalientes', 'BC': 'Baja California',
      'BS': 'Baja California Sur', 'CC': 'Campeche', 'CL': 'Coahuila',
      'CM': 'Colima', 'CS': 'Chiapas', 'CH': 'Chihuahua',
      'DF': 'Ciudad de Mexico', 'DG': 'Durango', 'GT': 'Guanajuato',
      'GR': 'Guerrero', 'HG': 'Hidalgo', 'JC': 'Jalisco',
      'MC': 'Estado de Mexico', 'MN': 'Michoacan', 'MS': 'Morelos',
      'NT': 'Nayarit', 'NL': 'Nuevo Leon', 'OC': 'Oaxaca', 'PL': 'Puebla',
      'QT': 'Queretaro', 'QR': 'Quintana Roo', 'SP': 'San Luis Potosi',
      'SL': 'Sinaloa', 'SR': 'Sonora', 'TC': 'Tabasco', 'TS': 'Tamaulipas',
      'TL': 'Tlaxcala', 'VZ': 'Veracruz', 'YN': 'Yucatan', 'ZS': 'Zacatecas',
      'NE': 'Nacido en el extranjero',
    };
    final ent = entidades[curp.substring(11, 13)] ?? curp.substring(11, 13);
    return {
      'valida': true,
      'fecha': '$dd/$mm/$anio',
      'sexo': sexo,
      'entidad': ent,
    };
  }

  /* ---------------- M3: Generar folio ---------------- */
  Future<void> _generarFolio() async {
    setState(() => _procesando = true);
    try {
      final resp = await http
          .get(Uri.parse('$guardianUrl?accion=generar_folio'))
          .timeout(const Duration(seconds: 45));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      final folio = (data['folio'] ?? '').toString();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Folio generado'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SelectableText(folio,
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: cessumRed)),
              const SizedBox(height: 6),
              Text('${data['fecha']}',
                  style: TextStyle(fontSize: 12, color: cessumMuted(context))),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: folio));
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                    content: Text('Folio copiado'),
                  ));
                }
              },
              child: const Text('Copiar'),
            ),
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cerrar')),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text('No se pudo: $e'.replaceAll('Exception: ', '')),
        ));
      }
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  /* ---------------- M3: Exportar calificaciones de un grupo ---------------- */
  Future<void> _exportarCalif() async {
    final programa = TextEditingController();
    final generacion = TextEditingController();
    final grupo = TextEditingController();
    final clave = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Exportar calificaciones',
            style: TextStyle(fontSize: 16)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: programa,
                decoration: const InputDecoration(
                  labelText: 'Programa *',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: generacion,
                decoration: const InputDecoration(
                  labelText: 'Generación',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: grupo,
                      decoration: const InputDecoration(
                        labelText: 'Grupo *',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: clave,
                      decoration: const InputDecoration(
                        labelText: 'Clave materia',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () {
              if (programa.text.trim().isEmpty || grupo.text.trim().isEmpty) {
                return;
              }
              Navigator.pop(ctx, true);
            },
            child: const Text('Exportar'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _procesando = true);
    try {
      final uri = Uri.parse('$guardianUrl?accion=exportar_calif_csv'
          '&programa=${Uri.encodeComponent(programa.text.trim())}'
          '&generacion=${Uri.encodeComponent(generacion.text.trim())}'
          '&grupo=${Uri.encodeComponent(grupo.text.trim())}'
          '&clave=${Uri.encodeComponent(clave.text.trim())}');
      final resp = await http.get(uri).timeout(const Duration(seconds: 90));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      final csv = (data['csv'] ?? '').toString();
      if (!mounted) return;
      await _mostrarCsv(
          'Calificaciones (${data['filas']}) - prom. ${data['promedio']}', csv);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text('No se pudo: $e'.replaceAll('Exception: ', '')),
        ));
      }
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  /* ---------------- M4: Alumnos sin CURP ---------------- */
  Future<void> _sinCurp() async {
    setState(() => _procesando = true);
    try {
      final resp = await http
          .get(Uri.parse('$guardianUrl?accion=alumnos_sin_curp'))
          .timeout(const Duration(seconds: 90));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      final csv = (data['csv'] ?? '').toString();
      final filas = (data['filas'] ?? 0);
      if (!mounted) return;
      await _mostrarCsv('Alumnos sin CURP ($filas)', csv);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text('No se pudo: $e'.replaceAll('Exception: ', '')),
        ));
      }
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  /* ---------------- M4: Duplicados de matricula ---------------- */
  Future<void> _duplicados() async {
    setState(() => _procesando = true);
    try {
      final resp = await http
          .get(Uri.parse('$guardianUrl?accion=duplicados_matricula'))
          .timeout(const Duration(seconds: 90));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      final dups = ((data['duplicados'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Matriculas duplicadas (${dups.length})',
              style: const TextStyle(fontSize: 15)),
          content: SizedBox(
            width: double.maxFinite,
            child: dups.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('No hay matriculas duplicadas. Todo limpio.'),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: ListView(
                          shrinkWrap: true,
                          children: dups.map((d) {
                            final nombres =
                                (d['nombres'] as List?)?.join(' · ') ?? '';
                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.warning_amber,
                                  color: cessumRed, size: 20),
                              title: Text('${d['matricula']} (${d['veces']}x)',
                                  style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700)),
                              subtitle: Text(nombres,
                                  style: const TextStyle(fontSize: 11)),
                            );
                          }).toList(),
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
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text('No se pudo: $e'.replaceAll('Exception: ', '')),
        ));
      }
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  /* ---------------- M4: Resumen de pendientes ---------------- */
  Future<void> _resumenPendientes() async {
    setState(() => _procesando = true);
    try {
      final resp = await http
          .get(Uri.parse('$guardianUrl?accion=resumen_pendientes'))
          .timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      final items = ((data['items'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final total = (data['total'] ?? 0);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Pendientes (total: $total)',
              style: const TextStyle(fontSize: 15)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: items.map((it) {
              final cant = (it['cantidad'] ?? 0);
              return ListTile(
                dense: true,
                title: Text('${it['tipo']}',
                    style: const TextStyle(fontSize: 12.5)),
                trailing: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: (cant == 0 ? cessumFaint(context) : cessumRed)
                        .withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('$cant',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: cant == 0 ? cessumMuted(context) : cessumRed)),
                ),
              );
            }).toList(),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cerrar')),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text('No se pudo: $e'.replaceAll('Exception: ', '')),
        ));
      }
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  /* ---------------- M5: Lista de asistencia (PDF) ---------------- */
  Future<void> _listaAsistencia() async {
    final programa = TextEditingController();
    final generacion = TextEditingController();
    final grupo = TextEditingController();
    final materia = TextEditingController();
    final sesiones = TextEditingController(text: '8');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Lista de asistencia', style: TextStyle(fontSize: 16)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: programa,
                decoration: const InputDecoration(
                  labelText: 'Programa *',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: generacion,
                decoration: const InputDecoration(
                  labelText: 'Generación',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: grupo,
                      decoration: const InputDecoration(
                        labelText: 'Grupo *',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 90,
                    child: TextField(
                      controller: sesiones,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Columnas',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: materia,
                decoration: const InputDecoration(
                  labelText: 'Materia (opcional)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () {
              if (programa.text.trim().isEmpty || grupo.text.trim().isEmpty) {
                return;
              }
              Navigator.pop(ctx, true);
            },
            child: const Text('Generar'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _procesando = true);
    try {
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'lista_asistencia_pdf',
                'actor': _correoActor,
                'programa': programa.text.trim(),
                'generacion': generacion.text.trim(),
                'grupo': grupo.text.trim(),
                'materia': materia.text.trim(),
                'sesiones': sesiones.text.trim(),
              }))
          .timeout(const Duration(seconds: 90));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      final pdf = (data['pdf'] ?? '').toString();
      if (!mounted) return;
      if (pdf.isNotEmpty) Helpers.abrirUrlExterna(pdf, context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.green,
        content: Text('Lista generada (${data['alumnos']} alumnos).'),
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text('No se pudo: $e'.replaceAll('Exception: ', '')),
        ));
      }
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  /* ---------------- M5: Buscar docente por materia ---------------- */
  Future<void> _buscarDocente() async {
    final q = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => _BuscarDocenteDialog(controller: q),
    );
  }

  /* ---------------- M5: Estado del sistema ---------------- */
  Future<void> _estadoSistema() async {
    setState(() => _procesando = true);
    try {
      final resp = await http
          .get(Uri.parse('$guardianUrl?accion=estado_sistema'))
          .timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final fuentes = ((data['fuentes'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Estado del sistema', style: TextStyle(fontSize: 15)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Hora del servidor: ${data['hora'] ?? ''}',
                  style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
              const Divider(),
              ...fuentes.map((f) {
                final bien = f['ok'] == true;
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(bien ? Icons.check_circle : Icons.error,
                      color: bien ? const Color(0xFF1E8E3E) : cessumRed,
                      size: 20),
                  title: Text('${f['nombre']}',
                      style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w700)),
                  subtitle: Text('${f['detalle']}',
                      style: const TextStyle(fontSize: 11)),
                );
              }),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cerrar')),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text('No se pudo: $e'.replaceAll('Exception: ', '')),
        ));
      }
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  /* ---------------- M6: Reconocimientos por lote ---------------- */
  Future<void> _reconocimientoLote() async {
    final nombres = TextEditingController();
    final motivo = TextEditingController();
    final fecha = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reconocimientos por lote',
            style: TextStyle(fontSize: 16)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nombres,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'Nombres (uno por linea) *',
                  hintText: 'Juan Perez\nMaria Lopez\n...',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: motivo,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Motivo (igual para todos) *',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: fecha,
                decoration: const InputDecoration(
                  labelText: 'Fecha/lugar (opcional)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () {
              if (nombres.text.trim().isEmpty || motivo.text.trim().isEmpty) {
                return;
              }
              Navigator.pop(ctx, true);
            },
            child: const Text('Generar'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _procesando = true);
    try {
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'reconocimiento_lote',
                'actor': _correoActor,
                'nombres': nombres.text.trim(),
                'motivo': motivo.text.trim(),
                'fecha': fecha.text.trim(),
              }))
          .timeout(const Duration(seconds: 120));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      final pdf = (data['pdf'] ?? '').toString();
      if (!mounted) return;
      if (pdf.isNotEmpty) Helpers.abrirUrlExterna(pdf, context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.green,
        content: Text('${data['total']} reconocimientos generados.'),
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text('No se pudo: $e'.replaceAll('Exception: ', '')),
        ));
      }
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  /* ---------------- M6: Correos de un grupo (BCC) ---------------- */
  Future<void> _correosGrupo() async {
    final programa = TextEditingController();
    final generacion = TextEditingController();
    final grupo = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Correos de un grupo', style: TextStyle(fontSize: 16)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: programa,
                decoration: const InputDecoration(
                  labelText: 'Programa *',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: generacion,
                decoration: const InputDecoration(
                  labelText: 'Generación',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: grupo,
                decoration: const InputDecoration(
                  labelText: 'Grupo *',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () {
              if (programa.text.trim().isEmpty || grupo.text.trim().isEmpty) {
                return;
              }
              Navigator.pop(ctx, true);
            },
            child: const Text('Obtener'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _procesando = true);
    try {
      final uri = Uri.parse('$guardianUrl?accion=correos_grupo'
          '&programa=${Uri.encodeComponent(programa.text.trim())}'
          '&generacion=${Uri.encodeComponent(generacion.text.trim())}'
          '&grupo=${Uri.encodeComponent(grupo.text.trim())}');
      final resp = await http.get(uri).timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      final correos = (data['correos'] ?? '').toString();
      if (!mounted) return;
      await _mostrarCsv('Correos del grupo (${data['total']})', correos);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text('No se pudo: $e'.replaceAll('Exception: ', '')),
        ));
      }
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  /* ---------------- M6: Enlace de WhatsApp (local) ---------------- */
  Future<void> _enlaceWhatsapp() async {
    final numero = TextEditingController();
    final mensaje = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enlace de WhatsApp', style: TextStyle(fontSize: 16)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: numero,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Número (10 digitos) *',
                  hintText: '6421234567',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: mensaje,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Mensaje (opcional)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF25D366),
                foregroundColor: Colors.white),
            onPressed: () {
              var num = numero.text.trim().replaceAll(RegExp(r'[^0-9]'), '');
              if (num.length == 10) num = '52$num';
              if (num.isEmpty) return;
              final msg = Uri.encodeComponent(mensaje.text.trim());
              final url = 'https://wa.me/$num'
                  '${msg.isNotEmpty ? '?text=$msg' : ''}';
              Navigator.pop(ctx);
              Helpers.abrirUrlExterna(url, context);
            },
            child: const Text('Abrir chat'),
          ),
        ],
      ),
    );
  }

  /* ---------------- M7: Conversor calificacion a letra (local) ---------------- */
  Future<void> _conversorLetra() async {
    final num = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setS) {
          final letra = _numeroALetra(num.text.trim());
          return AlertDialog(
            title: const Text('Calificación a letra',
                style: TextStyle(fontSize: 16)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: num,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setS(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Calificación (0 a 10)',
                    hintText: 'Ej. 8.5',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 14),
                if (letra.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cessumRed.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SelectableText(letra,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: cessumRed)),
                  ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx2),
                  child: const Text('Cerrar')),
            ],
          );
        },
      ),
    );
  }

  String _numeroALetra(String texto) {
    if (texto.isEmpty) return '';
    final n = double.tryParse(texto.replaceAll(',', '.'));
    if (n == null || n < 0 || n > 10) return 'Valor entre 0 y 10';
    const unidades = [
      'CERO', 'UNO', 'DOS', 'TRES', 'CUATRO', 'CINCO',
      'SEIS', 'SIETE', 'OCHO', 'NUEVE', 'DIEZ'
    ];
    final entero = n.floor();
    final decimal = ((n - entero) * 10).round();
    final base = unidades[entero];
    if (decimal == 0) return base;
    return '$base PUNTO ${unidades[decimal]}';
  }

  /* ---------------- M7: Oficio en blanco (PDF) ---------------- */
  Future<void> _oficio() async {
    final destinatario = TextEditingController();
    final asunto = TextEditingController();
    final cuerpo = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Oficio institucional', style: TextStyle(fontSize: 16)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: destinatario,
                decoration: const InputDecoration(
                  labelText: 'Destinatario',
                  hintText: 'A quien corresponda',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: asunto,
                decoration: const InputDecoration(
                  labelText: 'Asunto',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: cuerpo,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Cuerpo (puedes dejarlo para llenar a mano)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Generar'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _procesando = true);
    try {
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'oficio_pdf',
                'actor': _correoActor,
                'destinatario': destinatario.text.trim(),
                'asunto': asunto.text.trim(),
                'cuerpo': cuerpo.text.trim(),
              }))
          .timeout(const Duration(seconds: 90));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      final pdf = (data['pdf'] ?? '').toString();
      if (!mounted) return;
      if (pdf.isNotEmpty) Helpers.abrirUrlExterna(pdf, context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.green,
        content: Text('Oficio generado (folio ${data['folio']}).'),
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text('No se pudo: $e'.replaceAll('Exception: ', '')),
        ));
      }
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  /* ---------------- M7: Exportar directorio docentes CSV ---------------- */
  Future<void> _docentesCsv() async {
    setState(() => _procesando = true);
    try {
      final resp = await http
          .get(Uri.parse('$guardianUrl?accion=exportar_docentes_csv'))
          .timeout(const Duration(seconds: 90));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      final csv = (data['csv'] ?? '').toString();
      final filas = (data['filas'] ?? 0);
      if (!mounted) return;
      await _mostrarCsv('Directorio de docentes ($filas)', csv);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text('No se pudo: $e'.replaceAll('Exception: ', '')),
        ));
      }
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  /* ---------------- M8: Resumen de calificaciones por programa ---------------- */
  Future<void> _resumenCalif() async {
    setState(() => _procesando = true);
    try {
      final resp = await http
          .get(Uri.parse('$guardianUrl?accion=resumen_calif_programa'))
          .timeout(const Duration(seconds: 90));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      final progs = ((data['programas'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Calificaciones por programa (${data['total']} reg.)',
              style: const TextStyle(fontSize: 14)),
          content: SizedBox(
            width: double.maxFinite,
            child: progs.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('Aun no hay calificaciones registradas.'),
                  )
                : ListView(
                    shrinkWrap: true,
                    children: progs.map((p) {
                      final ap = (p['aprobacion'] ?? 0) as int;
                      final color = ap >= 90
                          ? const Color(0xFF1E8E3E)
                          : (ap >= 70 ? cessumGold : cessumRed);
                      return Card(
                        margin: const EdgeInsets.only(bottom: 6),
                        child: ListTile(
                          dense: true,
                          title: Text('${p['programa']}',
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w700)),
                          subtitle: Text('${p['registros']} calificaciones',
                              style: const TextStyle(fontSize: 10.5)),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('Prom. ${p['promedio']}',
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      color: cessumRed)),
                              Text('$ap% aprob.',
                                  style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      color: color)),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cerrar')),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text('No se pudo: $e'.replaceAll('Exception: ', '')),
        ));
      }
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  /* ---------------- M8: Contador de dias para una fecha (local) ---------------- */
  Future<void> _contadorDias() async {
    DateTime? fecha;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setS) {
          String resultado = '';
          if (fecha != null) {
            final hoy = DateTime.now();
            final hoy0 = DateTime(hoy.year, hoy.month, hoy.day);
            final f0 = DateTime(fecha!.year, fecha!.month, fecha!.day);
            final dias = f0.difference(hoy0).inDays;
            if (dias == 0) {
              resultado = 'Es hoy';
            } else if (dias > 0) {
              resultado = 'Faltan $dias dia(s)';
            } else {
              resultado = 'Hace ${-dias} dia(s)';
            }
          }
          return AlertDialog(
            title: const Text('Contador de dias', style: TextStyle(fontSize: 16)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    final hoy = DateTime.now();
                    final sel = await showDatePicker(
                      context: ctx2,
                      initialDate: fecha ?? hoy,
                      firstDate: DateTime(hoy.year - 2),
                      lastDate: DateTime(hoy.year + 5),
                    );
                    if (sel != null) setS(() => fecha = sel);
                  },
                  icon: const Icon(Icons.event),
                  label: Text(fecha == null
                      ? 'Elegir fecha'
                      : '${fecha!.day}/${fecha!.month}/${fecha!.year}'),
                ),
                const SizedBox(height: 14),
                if (resultado.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cessumRed.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(resultado,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: cessumRed)),
                  ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx2),
                  child: const Text('Cerrar')),
            ],
          );
        },
      ),
    );
  }

  /* ---------------- M8: Normalizar lista de nombres (local) ---------------- */
  Future<void> _normalizarNombres() async {
    final entrada = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setS) {
          final salida = entrada.text
              .split('\n')
              .map((l) => _aTituloCaso(l.trim()))
              .where((l) => l.isNotEmpty)
              .join('\n');
          return AlertDialog(
            title: const Text('Normalizar nombres',
                style: TextStyle(fontSize: 16)),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: entrada,
                    maxLines: 5,
                    onChanged: (_) => setS(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Pega los nombres (uno por linea)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  if (salida.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(maxHeight: 160),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: cessumMuted(context).withValues(alpha: 0.10), // (24-sep) modo oscuro
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SingleChildScrollView(
                        child: SelectableText(salida,
                            style: const TextStyle(fontSize: 12)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: salida));
                  if (ctx2.mounted) {
                    ScaffoldMessenger.of(ctx2).showSnackBar(const SnackBar(
                      content: Text('Copiado'),
                    ));
                  }
                },
                child: const Text('Copiar'),
              ),
              TextButton(
                  onPressed: () => Navigator.pop(ctx2),
                  child: const Text('Cerrar')),
            ],
          );
        },
      ),
    );
  }

  String _aTituloCaso(String s) {
    if (s.isEmpty) return '';
    return s
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  /* ---------------- M9: Reporte ejecutivo (PDF) ---------------- */
  Future<void> _reporteEjecutivo() async {
    setState(() => _procesando = true);
    try {
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'reporte_ejecutivo_pdf',
                'actor': _correoActor,
              }))
          .timeout(const Duration(seconds: 120));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      final pdf = (data['pdf'] ?? '').toString();
      if (!mounted) return;
      if (pdf.isNotEmpty) Helpers.abrirUrlExterna(pdf, context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.green,
        content: Text('Reporte generado (folio ${data['folio']}).'),
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text('No se pudo: $e'.replaceAll('Exception: ', '')),
        ));
      }
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  /* ---------------- M9: Calcular edad (local) ---------------- */
  Future<void> _calcularEdad() async {
    DateTime? nac;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setS) {
          String resultado = '';
          if (nac != null) {
            final hoy = DateTime.now();
            int anios = hoy.year - nac!.year;
            if (hoy.month < nac!.month ||
                (hoy.month == nac!.month && hoy.day < nac!.day)) {
              anios--;
            }
            resultado = '$anios años';
          }
          return AlertDialog(
            title: const Text('Calcular edad', style: TextStyle(fontSize: 16)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    final hoy = DateTime.now();
                    final sel = await showDatePicker(
                      context: ctx2,
                      initialDate: nac ?? DateTime(hoy.year - 20),
                      firstDate: DateTime(1940),
                      lastDate: hoy,
                    );
                    if (sel != null) setS(() => nac = sel);
                  },
                  icon: const Icon(Icons.cake),
                  label: Text(nac == null
                      ? 'Elegir fecha de nacimiento'
                      : '${nac!.day}/${nac!.month}/${nac!.year}'),
                ),
                const SizedBox(height: 14),
                if (resultado.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cessumRed.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(resultado,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: cessumRed)),
                  ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx2),
                  child: const Text('Cerrar')),
            ],
          );
        },
      ),
    );
  }

  /* ---------------- M10: Exportar padron completo ---------------- */
  Future<void> _exportarPadron() async {
    setState(() => _procesando = true);
    try {
      final resp = await http
          .get(Uri.parse('$guardianUrl?accion=exportar_padron_csv'))
          .timeout(const Duration(seconds: 90));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      final csv = (data['csv'] ?? '').toString();
      if (!mounted) return;
      await _mostrarCsv(
          'Padron completo (${data['activos']} activos, ${data['bajas']} bajas)',
          csv);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text('No se pudo: $e'.replaceAll('Exception: ', '')),
        ));
      }
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  /* ---------------- M10: Buscar por CURP ---------------- */
  Future<void> _buscarPorCurp() async {
    final q = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => _BuscarCurpDialog(controller: q),
    );
  }

  /* ---------------- compartido: mostrar CSV ---------------- */
  Future<void> _mostrarCsv(String titulo, String csv) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo, style: const TextStyle(fontSize: 15)),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Copia el texto y pegalo en Excel o Google Sheets (cada renglon es una fila).',
                style: TextStyle(fontSize: 12, color: cessumMuted(context)),
              ),
              const SizedBox(height: 10),
              Container(
                constraints: const BoxConstraints(maxHeight: 220),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cessumMuted(context).withValues(alpha: 0.10), // (24-sep) modo oscuro
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(csv,
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 11)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: csv));
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                  content: Text('Copiado al portapapeles'),
                ));
              }
            },
            child: const Text('Copiar todo'),
          ),
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cerrar')),
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
        title: const Text('Herramientas',
            style: TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _item(
                icon: Icons.workspace_premium,
                titulo: 'Constancia de reconocimiento',
                desc:
                    'Genera un reconocimiento en PDF con nombre y motivo (talleres, eventos, servicio).',
                onTap: _procesando ? null : _reconocimiento,
              ),
              _item(
                icon: Icons.badge_outlined,
                titulo: 'Validar CURP',
                desc:
                    'Verifica el formato de una CURP y extrae fecha, sexo y entidad.',
                onTap: _procesando ? null : _validarCurp,
              ),
              _item(
                icon: Icons.confirmation_number,
                titulo: 'Generar folio',
                desc: 'Reserva un folio institucional consecutivo.',
                onTap: _procesando ? null : _generarFolio,
              ),
              _item(
                icon: Icons.table_view,
                titulo: 'Exportar alumnos a CSV',
                desc:
                    'Lista de alumnos activos lista para pegar en Excel o Sheets.',
                onTap: _procesando ? null : _exportarCsv,
              ),
              _item(
                icon: Icons.grading,
                titulo: 'Exportar calificaciones de un grupo',
                desc:
                    'Concentrado de calificaciones de un grupo, en CSV, con promedio.',
                onTap: _procesando ? null : _exportarCalif,
              ),
              _item(
                icon: Icons.person_search,
                titulo: 'Alumnos sin CURP',
                desc:
                    'Lista de alumnos activos a los que les falta CURP, en CSV.',
                onTap: _procesando ? null : _sinCurp,
              ),
              _item(
                icon: Icons.content_copy,
                titulo: 'Matriculas duplicadas',
                desc:
                    'Detecta matriculas repetidas en el padron para corregirlas.',
                onTap: _procesando ? null : _duplicados,
              ),
              _item(
                icon: Icons.pending_actions,
                titulo: 'Resumen de pendientes',
                desc:
                    'Cuantos tramites, incidencias y solicitudes estan pendientes.',
                onTap: _procesando ? null : _resumenPendientes,
              ),
              _item(
                icon: Icons.fact_check,
                titulo: 'Lista de asistencia (PDF)',
                desc:
                    'Genera una lista en blanco de un grupo, lista para imprimir.',
                onTap: _procesando ? null : _listaAsistencia,
              ),
              _item(
                icon: Icons.person_pin,
                titulo: 'Buscar docente por materia',
                desc: 'Encuentra quien imparte una materia y en que grupo.',
                onTap: _procesando ? null : _buscarDocente,
              ),
              _item(
                icon: Icons.monitor_heart,
                titulo: 'Estado del sistema',
                desc:
                    'Verifica que el padron, las cartas y la base respondan bien.',
                onTap: _procesando ? null : _estadoSistema,
              ),
              _item(
                icon: Icons.groups,
                titulo: 'Reconocimientos por lote',
                desc:
                    'Pega una lista de nombres y genera un PDF con un reconocimiento por persona.',
                onTap: _procesando ? null : _reconocimientoLote,
              ),
              _item(
                icon: Icons.alternate_email,
                titulo: 'Correos de un grupo',
                desc:
                    'Lista de correos separados por coma, lista para pegar en copia oculta (BCC).',
                onTap: _procesando ? null : _correosGrupo,
              ),
              _item(
                icon: Icons.chat,
                titulo: 'Enlace de WhatsApp',
                desc:
                    'Arma un enlace wa.me con numero y mensaje para abrir un chat al instante.',
                onTap: _procesando ? null : _enlaceWhatsapp,
              ),
              _item(
                icon: Icons.spellcheck,
                titulo: 'Calificación a letra',
                desc:
                    'Convierte un numero (0 a 10) a su forma en letra, al instante.',
                onTap: _procesando ? null : _conversorLetra,
              ),
              _item(
                icon: Icons.description,
                titulo: 'Oficio institucional (PDF)',
                desc:
                    'Genera un oficio con folio, encabezado y cuerpo, listo para imprimir.',
                onTap: _procesando ? null : _oficio,
              ),
              _item(
                icon: Icons.import_contacts,
                titulo: 'Exportar directorio docente',
                desc:
                    'Directorio de docentes con correo y materias, en CSV.',
                onTap: _procesando ? null : _docentesCsv,
              ),
              _item(
                icon: Icons.bar_chart,
                titulo: 'Calificaciones por programa',
                desc:
                    'Promedio y porcentaje de aprobacion de cada programa.',
                onTap: _procesando ? null : _resumenCalif,
              ),
              _item(
                icon: Icons.hourglass_bottom,
                titulo: 'Contador de dias',
                desc:
                    'Cuantos dias faltan (o pasaron) para una fecha clave.',
                onTap: _procesando ? null : _contadorDias,
              ),
              _item(
                icon: Icons.text_fields,
                titulo: 'Normalizar nombres',
                desc:
                    'Limpia y estandariza una lista de nombres a formato titulo.',
                onTap: _procesando ? null : _normalizarNombres,
              ),
              _item(
                icon: Icons.assessment,
                titulo: 'Reporte ejecutivo (PDF)',
                desc:
                    'Numeros clave, desempeno por programa y pendientes, en un PDF para juntas.',
                onTap: _procesando ? null : _reporteEjecutivo,
              ),
              _item(
                icon: Icons.cake_outlined,
                titulo: 'Calcular edad',
                desc:
                    'A partir de una fecha de nacimiento, calcula la edad exacta.',
                onTap: _procesando ? null : _calcularEdad,
              ),
              _item(
                icon: Icons.dataset,
                titulo: 'Exportar padron completo',
                desc:
                    'Todo el padron (activos y bajas) con CURP y estatus, en CSV.',
                onTap: _procesando ? null : _exportarPadron,
              ),
              _item(
                icon: Icons.fingerprint,
                titulo: 'Buscar por CURP',
                desc:
                    'Encuentra a un alumno escribiendo parte o toda su CURP.',
                onTap: _procesando ? null : _buscarPorCurp,
              ),
            ],
          ),
          if (_procesando)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(color: cessumRed),
            ),
        ],
      ),
    );
  }

  Widget _item({
    required IconData icon,
    required String titulo,
    required String desc,
    required VoidCallback? onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: cessumRed.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: cessumRed),
        ),
        title: Text(titulo,
            style:
                const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
        subtitle: Text(desc,
            style: const TextStyle(fontSize: 11.5, height: 1.3)),
        trailing: const Icon(Icons.chevron_right, color: cessumRed),
        onTap: onTap,
      ),
    );
  }
}

class _BuscarDocenteDialog extends StatefulWidget {
  final TextEditingController controller;
  const _BuscarDocenteDialog({required this.controller});

  @override
  State<_BuscarDocenteDialog> createState() => _BuscarDocenteDialogState();
}

class _BuscarDocenteDialogState extends State<_BuscarDocenteDialog> {
  List<Map<String, dynamic>> _res = [];
  bool _buscando = false;

  Future<void> _buscar(String q) async {
    if (q.trim().length < 2) {
      setState(() => _res = []);
      return;
    }
    setState(() => _buscando = true);
    try {
      final resp = await http
          .get(Uri.parse(
              '$guardianUrl?accion=buscar_docente_materia&q=${Uri.encodeComponent(q.trim())}'))
          .timeout(const Duration(seconds: 45));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _res = ((data['resultados'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _buscando = false;
      });
    } catch (e) {
      if (mounted) setState(() => _buscando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Buscar docente por materia',
          style: TextStyle(fontSize: 15)),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: widget.controller,
              onChanged: _buscar,
              decoration: InputDecoration(
                hintText: 'Nombre de la materia...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _buscando
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                            width: 16,
                            height: 16,
                            child:
                                CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : null,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: _res.isEmpty
                  ? Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('Escribe una materia para buscar.',
                          style: TextStyle(color: cessumMuted(context))),
                    )
                  : ListView(
                      shrinkWrap: true,
                      children: _res.map((r) {
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.school,
                              color: cessumGold, size: 20),
                          title: Text('${r['docente']}',
                              style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700)),
                          subtitle: Text(
                            '${r['materia']}\n${r['generacion']} G${r['grupo']} · ${r['correo']}',
                            style: const TextStyle(
                                fontSize: 10.5, height: 1.3),
                          ),
                          isThreeLine: true,
                        );
                      }).toList(),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar')),
      ],
    );
  }
}

class _BuscarCurpDialog extends StatefulWidget {
  final TextEditingController controller;
  const _BuscarCurpDialog({required this.controller});

  @override
  State<_BuscarCurpDialog> createState() => _BuscarCurpDialogState();
}

class _BuscarCurpDialogState extends State<_BuscarCurpDialog> {
  List<Map<String, dynamic>> _res = [];
  bool _buscando = false;

  Future<void> _buscar(String q) async {
    if (q.trim().length < 4) {
      setState(() => _res = []);
      return;
    }
    setState(() => _buscando = true);
    try {
      final resp = await http
          .get(Uri.parse(
              '$guardianUrl?accion=buscar_por_curp&q=${Uri.encodeComponent(q.trim())}'))
          .timeout(const Duration(seconds: 45));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _res = ((data['resultados'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _buscando = false;
      });
    } catch (e) {
      if (mounted) setState(() => _buscando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Buscar por CURP', style: TextStyle(fontSize: 15)),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: widget.controller,
              textCapitalization: TextCapitalization.characters,
              onChanged: _buscar,
              decoration: InputDecoration(
                hintText: 'Parte o toda la CURP...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _buscando
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                            width: 16,
                            height: 16,
                            child:
                                CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : null,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: _res.isEmpty
                  ? Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('Escribe al menos 4 caracteres de la CURP.',
                          style: TextStyle(color: cessumMuted(context))),
                    )
                  : ListView(
                      shrinkWrap: true,
                      children: _res.map((r) {
                        return ListTile(
                          dense: true,
                          leading: Icon(
                              r['baja'] == true
                                  ? Icons.person_off
                                  : Icons.person,
                              color: r['baja'] == true
                                  ? cessumFaint(context)
                                  : cessumRed,
                              size: 20),
                          title: Text('${r['nombre']}',
                              style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700)),
                          subtitle: Text(
                            '${r['curp']}\n${r['matricula']} · ${r['programa']}'
                            '${r['baja'] == true ? ' · BAJA' : ''}',
                            style: const TextStyle(
                                fontSize: 10.5, height: 1.3),
                          ),
                          isThreeLine: true,
                        );
                      }).toList(),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar')),
      ],
    );
  }
}

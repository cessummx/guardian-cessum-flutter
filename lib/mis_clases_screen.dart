import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'helpers.dart';
import 'student_profile.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

/// Pantalla "Mis clases" del alumno.
///
/// Muestra automáticamente las clases ACTIVAS de su grupo (materia, maestro,
/// día y hora) con botones directos a la videollamada y al Aula CESSUM.
/// El alumno no escribe nada: la app toma su matrícula del perfil, busca su
/// grupo en la base de organización y cruza con la agenda de profesores.
class MisClasesScreen extends StatefulWidget {
  const MisClasesScreen({super.key});

  @override
  State<MisClasesScreen> createState() => _MisClasesScreenState();
}

class _Clase {
  final String materia;
  final String clave;
  final String ciclo;
  final String tipoSesiones;
  final String dia;
  final String hora;
  final String docente;
  final String notas;
  final String linkLlamada;
  final String linkAula;

  _Clase({
    required this.materia,
    required this.clave,
    required this.ciclo,
    required this.tipoSesiones,
    required this.dia,
    required this.hora,
    required this.docente,
    required this.notas,
    required this.linkLlamada,
    required this.linkAula,
  });

  factory _Clase.fromJson(Map<String, dynamic> j) {
    String s(dynamic v) => (v ?? '').toString().trim();
    return _Clase(
      materia: s(j['materia']),
      clave: s(j['clave']),
      ciclo: s(j['ciclo']),
      tipoSesiones: s(j['tipoSesiones']),
      dia: s(j['dia']),
      hora: s(j['hora']),
      docente: s(j['docente']),
      notas: s(j['notas']),
      linkLlamada: s(j['linkLlamada']),
      linkAula: s(j['linkAula']),
    );
  }
}

class _MisClasesScreenState extends State<MisClasesScreen> {
  bool _cargando = true;
  String _error = '';
  List<_Clase> _clases = [];
  String _busqueda = '';

  List<_Clase> get _clasesFiltradas {
    final q = _busqueda.trim().toLowerCase();
    if (q.isEmpty) return _clases;
    return _clases
        .where((c) =>
            c.materia.toLowerCase().contains(q) ||
            c.clave.toLowerCase().contains(q) ||
            c.ciclo.toLowerCase().contains(q))
        .toList();
  }

  // Datos del grupo resueltos desde la base (para mostrarlos arriba).
  String _programa = '';
  String _generacion = '';
  String _grupo = '';

  // Colores que responden al tema (sin alterar el modo claro).
  Color get _superficie => Theme.of(context).cardColor;
  Color get _textoFuerte => cessumIsDark(context) ? Colors.white : cessumInk(context);
  Color get _textoSuave => cessumMuted(context);
  Color get _borde => cessumIsDark(context) ? Colors.white12 : cessumMuted(context).withValues(alpha: 0.18);

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
      // 1) Perfil del alumno (matrícula).
      final perfil = await StudentProfile.load();
      if (perfil == null || perfil.matricula.isEmpty) {
        setState(() {
          _cargando = false;
          _error =
              'No encontramos tu perfil. Vuelve a entrar a la app e identifícate.';
        });
        return;
      }

      // 2) Buscar su grupo en la base de organización (fuente oficial).
      String programa = perfil.programa;
      String generacion = perfil.generacion;
      String grupo = '';

      final uriGrupo = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'grupos_admin_buscar',
        'q': perfil.matricula,
      });
      final respGrupo =
          await http.get(uriGrupo).timeout(const Duration(seconds: 30));
      if (respGrupo.statusCode == 200) {
        final data = jsonDecode(respGrupo.body) as Map<String, dynamic>;
        if (data['ok'] == true && data['grupos'] is List) {
          for (final g in (data['grupos'] as List)) {
            final m = (g as Map<String, dynamic>);
            if ((m['matricula'] ?? '').toString().trim() == perfil.matricula) {
              programa = (m['programa'] ?? programa).toString().trim();
              generacion = (m['generacion'] ?? generacion).toString().trim();
              grupo = (m['grupo'] ?? '').toString().trim();
              break;
            }
          }
        }
      }

      // 3) Pedir las clases activas de su grupo.
      final uriClases = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'mis_clases',
        'programa': programa,
        'generacion': generacion,
        'grupo': grupo,
      });
      final resp =
          await http.get(uriClases).timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200) {
        throw Exception('Error de conexión (${resp.statusCode}).');
      }
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) {
        throw Exception((data['error'] ?? 'No se pudo cargar.').toString());
      }
      final lista = (data['clases'] as List? ?? [])
          .map((e) => _Clase.fromJson(e as Map<String, dynamic>))
          .toList();

      if (!mounted) return;
      setState(() {
        _programa = programa;
        _generacion = generacion;
        _grupo = grupo;
        _clases = lista;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error =
            'No pudimos cargar tus clases. Revisa tu conexión e intenta de nuevo.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Mis clases'),
      ),
      body: _cargando
          ? const CessumSkeletonList()
          : _error.isNotEmpty
              ? _vistaError()
              : RefreshIndicator(
                  color: cessumRed,
                  onRefresh: _cargar,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    children: [
                      _encabezadoGrupo(),
                      const SizedBox(height: 12),
                      if (_clases.isEmpty)
                        _vistaVacia()
                      else ...[
                        if (_clases.length > 4) ...[
                          _buscador(),
                          const SizedBox(height: 12),
                        ],
                        ..._clasesFiltradas.map(_tarjetaClase),
                        if (_clasesFiltradas.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                              child: Text(
                                'Ninguna clase coincide con la búsqueda.',
                                style: TextStyle(color: cessumMuted(context)),
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _buscador() {
    return TextField(
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Buscar materia, clave o ciclo',
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: _busqueda.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => setState(() => _busqueda = ''),
              ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onChanged: (v) => setState(() => _busqueda = v),
    );
  }

  Widget _vistaError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off, size: 48, color: cessumFaint(context)),
            const SizedBox(height: 12),
            Text(
              _error,
              textAlign: TextAlign.center,
              style: TextStyle(color: cessumMuted(context)),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed,
                foregroundColor: Colors.white,
              ),
              onPressed: _cargar,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _vistaVacia() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _superficie,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borde),
      ),
      child: Column(
        children: [
          Icon(Icons.event_available, size: 48, color: _textoSuave),
          const SizedBox(height: 12),
          Text(
            'Aún no hay clases registradas para tu grupo.',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w600, color: _textoFuerte),
          ),
          const SizedBox(height: 6),
          Text(
            'Cuando la coordinación agende tus sesiones, aparecerán aquí '
            'con sus links de videollamada y Aula.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _textoSuave, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _encabezadoGrupo() {
    final partes = <String>[];
    if (_programa.isNotEmpty) partes.add(_programa);
    if (_generacion.isNotEmpty) partes.add('Generación $_generacion');
    if (_grupo.isNotEmpty) partes.add('Grupo $_grupo');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cessumRed.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cessumRed.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.groups, color: cessumRed),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              partes.isEmpty ? 'Tu grupo' : partes.join(' · '),
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: cessumInk(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaClase(_Clase c) {
    final horario = [
      if (c.dia.isNotEmpty) c.dia,
      if (c.hora.isNotEmpty) c.hora,
    ].join(' · ');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _superficie,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borde),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            c.materia.isEmpty ? 'Materia' : c.materia,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: _textoFuerte,
            ),
          ),
          if (c.docente.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.person, size: 16, color: _textoSuave),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    c.docente,
                    style: TextStyle(color: _textoSuave),
                  ),
                ),
              ],
            ),
          ],
          if (horario.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.schedule, size: 16, color: _textoSuave),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    horario,
                    style: TextStyle(color: _textoSuave),
                  ),
                ),
              ],
            ),
          ],
          if (c.tipoSesiones.isNotEmpty || c.ciclo.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (c.tipoSesiones.isNotEmpty) _chip(c.tipoSesiones, cessumGold),
                if (c.ciclo.isNotEmpty) _chip('Ciclo ${c.ciclo}', cessumRed),
              ],
            ),
          ],
          if (c.notas.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              c.notas,
              style: TextStyle(
                color: _textoSuave,
                fontSize: 13,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          if (c.linkLlamada.isNotEmpty || c.linkAula.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (c.linkLlamada.isNotEmpty)
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: cessumRed,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () =>
                          Helpers.abrirUrlExterna(c.linkLlamada, context),
                      icon: const Icon(Icons.videocam, size: 20),
                      label: const Text('Videollamada'),
                    ),
                  ),
                if (c.linkLlamada.isNotEmpty && c.linkAula.isNotEmpty)
                  const SizedBox(width: 10),
                if (c.linkAula.isNotEmpty)
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: cessumRed,
                        side: const BorderSide(color: cessumRed),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () =>
                          Helpers.abrirUrlExterna(c.linkAula, context),
                      icon: const Icon(Icons.school, size: 20),
                      label: const Text('Aula'),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _chip(String texto, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        texto,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

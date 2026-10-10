// material_ia_hub_screen.dart
// ---------------------------------------------------------------------------
// (9-sep-2026) PLANEACIÓN Y DIAPOSITIVAS CON IA — una sola puerta.
//
// En «Material didáctico» vivían tres renglones sueltos: crear presentación,
// planeación didáctica y mis planeaciones. Puestos uno junto a otro parecían
// tres herramientas independientes, y no lo son: la presentación SOLO se arma
// con una planeación que Vicerrectoría ya dictaminó como validada. El docente
// que empezaba por el renglón de arriba chocaba con ese candado sin saber por
// qué existía.
//
// Esta pantalla los presenta como lo que son: tres pasos de un mismo ciclo,
// en orden, y le dice al docente en cuál va. Consulta `planea_mis_entregas`
// para saber si ya tiene alguna validada y pinta el paso 3 en consecuencia.
//
// DECISIÓN DELIBERADA: el paso 3 NUNCA se bloquea. Si todavía no hay ninguna
// planeación validada se muestra atenuado y con la explicación de qué falta,
// pero se puede entrar. Esconder el acceso a alguien que sí lo necesita —un
// docente que ya la tiene validada y la consulta no alcanzó a cargar, por
// ejemplo— es peor que dejarlo pasar y que el backend haga su trabajo.
// ---------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert' show jsonDecode;

import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'generador_diapositivas_screen.dart';
import 'planeacion_didactica_screen.dart';
import 'mis_planeaciones_screen.dart';

class MaterialIaHubScreen extends StatefulWidget {
  const MaterialIaHubScreen({super.key});

  @override
  State<MaterialIaHubScreen> createState() => _MaterialIaHubScreenState();
}

class _MaterialIaHubScreenState extends State<MaterialIaHubScreen> {
  bool _cargando = true;
  bool _fallo = false; // la consulta no respondió: no afirmamos nada

  // Recuento de entregas por estado, para decir en qué paso va.
  int _validadas = 0;
  int _enRevision = 0;
  int _conObservaciones = 0;
  final List<String> _materiasValidadas = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _fallo = false;
    });
    try {
      final correo = await SessionStore.validEmail() ?? '';
      if (correo.isEmpty) {
        if (mounted) setState(() { _cargando = false; _fallo = true; });
        return;
      }
      final uri = Uri.parse('$guardianUrl?accion=planea_mis_entregas'
          '&correo=${Uri.encodeComponent(correo)}'
          '&actor=${Uri.encodeComponent(correo)}');
      final resp = await http.get(uri).timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] != true) {
        setState(() { _cargando = false; _fallo = true; });
        return;
      }

      int val = 0, rev = 0, obs = 0;
      final materias = <String>[];
      final lista = (data['entregas'] as List?) ?? const [];
      for (final e in lista) {
        if (e is! Map) continue;
        final estado = (e['estado'] ?? '').toString().toLowerCase();
        final materia = (e['materia'] ?? '').toString().trim();
        // 'validada' es el estado que pone el dictamen de Vicerrectoría.
        if (estado.contains('valid')) {
          val++;
          if (materia.isNotEmpty && !materias.contains(materia)) {
            materias.add(materia);
          }
        } else if (estado.contains('observ')) {
          obs++;
        } else if (estado.contains('entreg') || estado.contains('revis')) {
          rev++;
        }
      }

      setState(() {
        _validadas = val;
        _enRevision = rev;
        _conObservaciones = obs;
        _materiasValidadas
          ..clear()
          ..addAll(materias);
        _cargando = false;
      });
    } catch (_) {
      if (mounted) setState(() { _cargando = false; _fallo = true; });
    }
  }

  bool get _hayValidada => _validadas > 0;

  void _ir(Widget pantalla) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => pantalla))
        .then((_) => _cargar()); // al volver, el estado del ciclo pudo cambiar
  }

  // El paso 3 informa en vez de bloquear.
  void _abrirPresentaciones() {
    if (_hayValidada || _fallo) {
      _ir(const GeneradorDiapositivasScreen());
      return;
    }
    showDialog<void>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('Aún no tienes una planeación validada'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _enRevision > 0
                  ? 'Tienes ${_enRevision == 1 ? "una planeación" : "$_enRevision planeaciones"} esperando el dictamen de Vicerrectoría. '
                      'En cuanto la validen, aquí podrás armar las presentaciones de esas sesiones.'
                  : _conObservaciones > 0
                      ? 'Vicerrectoría te devolvió ${_conObservaciones == 1 ? "una planeación" : "$_conObservaciones planeaciones"} con observaciones. '
                          'Atiéndelas y reenvíala para que quede validada.'
                      : 'Las presentaciones se arman a partir de una planeación validada, '
                          'para que las diapositivas correspondan a lo que se dictaminó. '
                          'Empieza por el paso 1.',
              style: const TextStyle(fontSize: 13.5, height: 1.35),
            ),
            const SizedBox(height: 12),
            Text(
              'Puedes entrar de todos modos: si tu planeación ya fue validada '
              'y esta pantalla no alcanzó a enterarse, el generador la va a encontrar.',
              style: TextStyle(fontSize: 12, height: 1.3, color: cessumMuted(context)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx),
            child: const Text('Entendido'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dctx);
              _ir(const GeneradorDiapositivasScreen());
            },
            child: const Text('Entrar de todos modos'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Planeación y Diapositivas con IA'),
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _encabezado(),
            const SizedBox(height: 18),
            _paso(
              numero: 1,
              icono: Icons.menu_book_outlined,
              titulo: 'Planeación didáctica',
              subtitulo:
                  'Dosifica tus sesiones y planéalas en inicio, desarrollo y cierre con abridores '
                  'para promover aprendizajes complejos. También puedes subir la tuya en el formato institucional.',
              activo: true,
              onTap: () => _ir(const PlaneacionDidacticaScreen()),
            ),
            _conector(),
            _paso(
              numero: 2,
              icono: Icons.fact_check_outlined,
              titulo: 'Mis planeaciones',
              subtitulo:
                  'Estatus de las que enviaste: en revisión, validadas o con observaciones. '
                  'Ábrelas y descárgalas.',
              activo: true,
              insignia: _insigniaPaso2(),
              onTap: () => _ir(const MisPlaneacionesScreen()),
            ),
            _conector(),
            _paso(
              numero: 3,
              icono: Icons.auto_awesome,
              titulo: 'Crear presentaciones',
              subtitulo: _hayValidada || _fallo
                  ? 'Arma la presentación de una sesión o el paquete completo de la asignatura, '
                      'con la identidad CESSUM, preguntas para el grupo y guion. Descargables en PPTX y PDF.'
                  : 'Se habilita con una planeación validada por Vicerrectoría, '
                      'para que las diapositivas correspondan a lo dictaminado.',
              activo: _hayValidada || _fallo,
              insignia: _insigniaPaso3(),
              onTap: _abrirPresentaciones,
            ),
            const SizedBox(height: 22),
            if (_fallo) _avisoSinDatos(),
          ],
        ),
      ),
    );
  }

  Widget _encabezado() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cessumRed.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cessumRed.withValues(alpha: 0.20)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.route_outlined, color: cessumRed, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Un solo camino, tres pasos',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: cessumIsDark(context) ? Colors.white : cessumInk(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Primero planeas, Vicerrectoría dictamina y, con la planeación validada, '
                  'la conviertes en presentaciones. Así las diapositivas siempre corresponden '
                  'a lo que se autorizó.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: cessumMuted(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget? _insigniaPaso2() {
    if (_cargando) return null;
    if (_conObservaciones > 0) {
      return _chip('$_conObservaciones con observaciones', cessumGold);
    }
    if (_enRevision > 0) {
      return _chip(
          '$_enRevision en revisión', cessumMuted(context));
    }
    if (_validadas > 0) {
      return _chip(
          '$_validadas validada${_validadas == 1 ? "" : "s"}', Colors.green.shade700);
    }
    return null;
  }

  Widget? _insigniaPaso3() {
    if (_cargando || _fallo) return null;
    if (_hayValidada) {
      final n = _materiasValidadas.length;
      return _chip(
          n == 1
              ? 'Lista: ${_materiasValidadas.first}'
              : '$n materias listas',
          Colors.green.shade700);
    }
    return _chip('Falta una planeación validada', cessumMuted(context));
  }

  Widget _chip(String texto, Color color) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        texto,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  // Hilo vertical que une un paso con el siguiente: el orden es el mensaje.
  Widget _conector() {
    return Padding(
      padding: const EdgeInsets.only(left: 31),
      child: Container(
        width: 2,
        height: 18,
        color: cessumMuted(context).withValues(alpha: 0.30),
      ),
    );
  }

  Widget _paso({
    required int numero,
    required IconData icono,
    required String titulo,
    required String subtitulo,
    required bool activo,
    required VoidCallback onTap,
    Widget? insignia,
  }) {
    final colorPunto = activo ? cessumRed : cessumMuted(context);
    return Material(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(12),
      elevation: 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Opacity(
          opacity: activo ? 1 : 0.62,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: colorPunto.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                        border: Border.all(color: colorPunto.withValues(alpha: 0.40)),
                      ),
                      child: Text(
                        '$numero',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: colorPunto,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Icon(icono, color: colorPunto, size: 18),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: cessumIsDark(context)
                              ? Colors.white
                              : cessumInk(context),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitulo,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          color: cessumMuted(context),
                        ),
                      ),
                      if (_cargando && numero > 1)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: SizedBox(
                            height: 12,
                            width: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: cessumMuted(context),
                            ),
                          ),
                        ),
                      if (insignia != null) insignia,
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.chevron_right, color: cessumMuted(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Si la consulta no respondió no se inventa un estado: se dice, y los tres
  // pasos quedan abiertos.
  Widget _avisoSinDatos() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline, size: 16, color: cessumMuted(context)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'No se pudo consultar el estatus de tus planeaciones en este momento, '
            'así que los tres pasos quedan disponibles. Desliza hacia abajo para reintentar.',
            style: TextStyle(fontSize: 11.5, height: 1.3, color: cessumMuted(context)),
          ),
        ),
      ],
    );
  }
}

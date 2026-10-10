// ============================================================================
//  MIS INVITACIONES · Aceptar o declinar una materia desde la app
//
//  Antes esto solo se podía hacer desde el correo. Quien lo borraba, lo perdía
//  entre otros mensajes o lo abría desde un teléfono donde el formulario no se
//  veía bien, tenía que pedir que se lo reenviaran.
//
//  La regla de los horarios NO vive aquí: la calcula el servidor y esta
//  pantalla la muestra. Duplicarla en el cliente es cómo se termina con dos
//  versiones que muestran cosas distintas, y ya pasó con la preselección.
// ============================================================================

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

class MisInvitacionesScreen extends StatefulWidget {
  final String correo;
  const MisInvitacionesScreen({super.key, required this.correo});

  @override
  State<MisInvitacionesScreen> createState() => _MisInvitacionesScreenState();
}

class _MisInvitacionesScreenState extends State<MisInvitacionesScreen> {
  bool _cargando = true;
  String? _error;
  List<Map<String, dynamic>> _invitaciones = [];

  /// Lo que el docente eligió en cada tarjeta, por fila de la asignación.
  final Map<int, String> _horaElegida = {};
  final Map<int, String> _diaElegido = {};
  final Map<int, TextEditingController> _comentarios = {};

  /// Fila que se está enviando ahora mismo. Evita el doble envío, que en una
  /// aceptación crea dos respuestas para la misma invitación.
  int? _enviando;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    for (final c in _comentarios.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'mis_invitaciones',
        'correo': widget.correo,
      });
      final r = await http.get(uri).timeout(const Duration(seconds: 60));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true) {
        throw Exception(d['error'] ?? 'No se pudieron cargar tus invitaciones.');
      }
      final lista = (d['invitaciones'] ?? d['lista'] ?? []) as List<dynamic>;
      final invs = lista.map((e) => Map<String, dynamic>.from(e as Map)).toList();

      // Se precarga lo que el servidor propone, para que el docente no tenga
      // que volver a elegir algo que ya se acordó con él.
      for (final inv in invs) {
        final fila = (inv['fila'] as num?)?.toInt() ?? 0;
        if (fila == 0) continue;
        _diaElegido[fila] = (inv['dia'] ?? '').toString();
        final ops = inv['opciones'] as Map<String, dynamic>?;
        final bloques = (ops?['bloques'] as List<dynamic>?) ?? const [];
        for (final b in bloques) {
          final m = Map<String, dynamic>.from(b as Map);
          if (m['preseleccionado'] == true) {
            _horaElegida[fila] = (m['horario'] ?? '').toString();
          }
        }
        _comentarios.putIfAbsent(fila, () => TextEditingController());
      }

      if (!mounted) return;
      setState(() {
        _invitaciones = invs;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _cargando = false;
      });
    }
  }

  Future<void> _responder(Map<String, dynamic> inv, bool acepta) async {
    final fila = (inv['fila'] as num?)?.toInt() ?? 0;
    if (fila == 0) return;

    final hora = _horaElegida[fila] ?? '';
    if (acepta && hora.isEmpty) {
      _aviso('Elige un horario antes de aceptar.', esError: true);
      return;
    }

    final materia = (inv['materia'] ?? '').toString();
    final grupo = (inv['grupo'] ?? '').toString();
    final dia = _diaElegido[fila] ?? (inv['dia'] ?? '').toString();

    // Aceptar una materia compromete meses de trabajo, y declinar libera el
    // grupo para otro docente. Ninguna de las dos debería ocurrir por un
    // toque accidental.
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(acepta ? '¿Aceptas impartirla?' : '¿Declinar esta materia?'),
        content: Text(
          acepta
              ? '$materia\n$grupo\n\n$dia, $hora\n\n'
                  'Al aceptar se crea tu aula y se inscriben los alumnos.'
              : '$materia\n$grupo\n\n'
                  'El grupo quedará libre para que se le ofrezca a otro docente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: acepta ? cessumRed : Colors.grey.shade700,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(acepta ? 'Sí, acepto' : 'Sí, declinar'),
          ),
        ],
      ),
    );
    if (confirmado != true) return;

    setState(() => _enviando = fila);
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'invitacion_responder_app',
        'correo': widget.correo,
        'fila': '$fila',
        'respuesta': acepta ? 'acepta' : 'rechaza',
        'dia': dia,
        'hora': hora,
        'comentarios': _comentarios[fila]?.text.trim() ?? '',
      });
      final r = await http.get(uri).timeout(const Duration(seconds: 60));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true) {
        throw Exception(d['error'] ?? 'No se pudo registrar tu respuesta.');
      }
      if (!mounted) return;
      _aviso(acepta
          ? 'Aceptada. Tu aula se está preparando y aparecerá en tu horario.'
          : 'Declinada. El grupo queda libre para otro docente.');
      await _cargar();
    } catch (e) {
      if (!mounted) return;
      _aviso(e.toString().replaceFirst('Exception: ', ''), esError: true);
    } finally {
      if (mounted) setState(() => _enviando = null);
    }
  }

  void _aviso(String texto, {bool esError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texto),
        backgroundColor: esError ? Colors.red.shade700 : const Color(0xFF1E8E3E),
        duration: Duration(seconds: esError ? 6 : 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg,
      appBar: AppBar(
        title: const Text('Mis invitaciones'),
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _cargando ? null : _cargar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _pantallaError()
              : _invitaciones.isEmpty
                  ? _sinInvitaciones()
                  : RefreshIndicator(
                      onRefresh: _cargar,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _invitaciones.length,
                        itemBuilder: (_, i) => _tarjeta(_invitaciones[i]),
                      ),
                    ),
    );
  }

  Widget _pantallaError() => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off, size: 46, color: Colors.grey.shade400),
              const SizedBox(height: 14),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 18),
              FilledButton(onPressed: _cargar, child: const Text('Reintentar')),
            ],
          ),
        ),
      );

  Widget _sinInvitaciones() => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.mark_email_read_outlined,
                  size: 46, color: Colors.grey.shade400),
              const SizedBox(height: 14),
              const Text('No tienes invitaciones pendientes.',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
              const SizedBox(height: 6),
              Text(
                'Cuando se te asigne una materia aparecerá aquí y también te '
                'llegará por correo.',
                textAlign: TextAlign.center,
                style: TextStyle(color: cessumMuted(context), fontSize: 13.5),
              ),
            ],
          ),
        ),
      );

  Widget _tarjeta(Map<String, dynamic> inv) {
    final fila = (inv['fila'] as num?)?.toInt() ?? 0;
    final materia = (inv['materia'] ?? '').toString();
    final programa = (inv['programa'] ?? '').toString();
    final gen = (inv['generacion'] ?? '').toString();
    final grupo = (inv['grupo'] ?? '').toString();
    final ops = inv['opciones'] as Map<String, dynamic>?;
    final bloques = (ops?['bloques'] as List<dynamic>?) ?? const [];
    final dia = _diaElegido[fila] ?? (inv['dia'] ?? '').toString();
    final nota = (ops?['nota'] ?? '').toString();
    final enviandoEsta = _enviando == fila;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(materia,
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.bold, height: 1.25)),
            const SizedBox(height: 5),
            Text('$programa · $gen · $grupo',
                style: TextStyle(fontSize: 13, color: cessumMuted(context))),
            const SizedBox(height: 14),

            Row(
              children: [
                Icon(Icons.event, size: 17, color: cessumGold),
                const SizedBox(width: 7),
                Text(dia.isEmpty ? 'Día por definir' : dia,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 12),

            const Text('Horario',
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                    color: Color(0xFFB08D57))),
            const SizedBox(height: 7),

            // Un bloque ocupado se muestra, no se esconde: el docente entiende
            // por qué no puede elegirlo, en vez de preguntarse dónde quedó.
            ...bloques.map((b) {
              final m = Map<String, dynamic>.from(b as Map);
              final horario = (m['horario'] ?? '').toString();
              final libre = m['disponible'] == true;
              final propuesto = m['propuesto'] == true;
              final motivo = (m['motivo'] ?? '').toString();
              final elegido = _horaElegida[fila] == horario;

              return InkWell(
                onTap: libre && !enviandoEsta
                    ? () => setState(() => _horaElegida[fila] = horario)
                    : null,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                  decoration: BoxDecoration(
                    color: elegido
                        ? cessumRed.withValues(alpha: 0.07)
                        : (libre ? Theme.of(context).cardColor : cessumMuted(context).withValues(alpha: 0.10)),
                    border: Border.all(
                      color: elegido ? cessumRed : const Color(0xFFE4DACA),
                      width: elegido ? 1.6 : 1,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        elegido
                            ? Icons.radio_button_checked
                            : (libre
                                ? Icons.radio_button_unchecked
                                : Icons.lock_outline),
                        size: 19,
                        color: elegido
                            ? cessumRed
                            : (libre ? Colors.grey.shade500 : Colors.grey.shade400),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              horario,
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight:
                                    elegido ? FontWeight.w700 : FontWeight.w500,
                                color: libre
                                    ? cessumInk(context)
                                    : Colors.grey.shade500,
                              ),
                            ),
                            if (motivo.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(motivo,
                                    style: TextStyle(
                                        fontSize: 11.5,
                                        color: cessumMuted(context))),
                              ),
                          ],
                        ),
                      ),
                      if (propuesto && libre)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 3),
                          decoration: BoxDecoration(
                            color: cessumGold.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text('propuesto',
                              style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: cessumGold)),
                        ),
                    ],
                  ),
                ),
              );
            }),

            if (nota.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(nota,
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey.shade700, height: 1.4)),
            ],

            const SizedBox(height: 14),
            TextField(
              controller: _comentarios[fila],
              maxLines: 2,
              enabled: !enviandoEsta,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                labelText: 'Comentarios (opcional)',
                hintText: 'Disponibilidad, requerimientos, dudas…',
                hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
                isDense: true,
              ),
            ),

            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed:
                        enviandoEsta ? null : () => _responder(inv, false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey.shade700,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    child: const Text('Declinar'),
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: enviandoEsta ? null : () => _responder(inv, true),
                    style: FilledButton.styleFrom(
                      backgroundColor: cessumRed,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    child: enviandoEsta
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Aceptar impartirla'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

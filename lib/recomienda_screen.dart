import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

/// Pantalla del alumno: programa "Recomienda". Genera un código único que
/// puede pasar a aspirantes. El aspirante paga menos en su inscripción y el
/// alumno recibe una bonificación para su próxima colegiatura (la habilita
/// administración de forma manual al verificar la inscripción).
class RecomiendaScreen extends StatefulWidget {
  final String matricula;
  final String nombre;
  const RecomiendaScreen(
      {super.key, required this.matricula, required this.nombre});

  @override
  State<RecomiendaScreen> createState() => _RecomiendaScreenState();
}

class _RecomiendaScreenState extends State<RecomiendaScreen> {
  bool _cargando = true;
  String? _error;
  String _codigo = '';
  int _descAspirante = 200;
  int _bonoAlumno = 250;
  int _totalBono = 0;
  List<Map<String, dynamic>> _referidos = [];

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
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'recomienda_alumno',
        'matricula': widget.matricula,
        'nombre': widget.nombre,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      int n(dynamic v) => v is int ? v : int.tryParse('$v') ?? 0;
      setState(() {
        _codigo = (data['codigo'] ?? '').toString();
        _descAspirante = n(data['descuentoAspirante']);
        _bonoAlumno = n(data['bonoAlumno']);
        _totalBono = n(data['totalBono']);
        _referidos = ((data['referidos'] as List<dynamic>? ?? []))
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _cargando = false;
      });
    } catch (e) {
      setState(() {
        _cargando = false;
        _error = '$e'.replaceAll('Exception: ', '');
      });
    }
  }

  String get _mensajeCompartir =>
      '¡Estudia en CESSUM! 🎓\n\nUsa mi código de recomendación *$_codigo* '
      'al inscribirte y obtén \$$_descAspirante de descuento en tu inscripción.\n\n'
      'Más informes por WhatsApp.';

  void _copiar(String texto, String aviso) {
    Clipboard.setData(ClipboardData(text: texto));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(aviso), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Recomienda'),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : _error != null
              ? Center(
                  child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.cloud_off, color: cessumRed, size: 44),
                    const SizedBox(height: 12),
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: cessumRed,
                          foregroundColor: Colors.white),
                      onPressed: _cargar,
                      child: const Text('Reintentar'),
                    ),
                  ]),
                ))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [cessumRed, Color(0xFF8E1622)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          const Text('Tu código de recomendación',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 13)),
                          const SizedBox(height: 8),
                          SelectableText(
                            _codigo,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 32,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: const BorderSide(color: Colors.white70),
                                ),
                                onPressed: () =>
                                    _copiar(_codigo, 'Código copiado'),
                                icon: const Icon(Icons.copy, size: 16),
                                label: const Text('Copiar código'),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: cessumRed,
                                ),
                                onPressed: () => _copiar(_mensajeCompartir,
                                    'Mensaje copiado, pégalo donde quieras'),
                                icon: const Icon(Icons.share, size: 16),
                                label: const Text('Compartir'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _comoFunciona(),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E8E3E).withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: const Color(0xFF1E8E3E).withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.savings, color: Color(0xFF1E8E3E)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Bonificación acumulada aprobada: \$$_totalBono '
                              'para tu próxima colegiatura.',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1E8E3E)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text('Tus recomendados',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: cessumRed)),
                    const SizedBox(height: 8),
                    if (_referidos.isEmpty)
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'Aún no tienes recomendados registrados. Comparte tu '
                          'código y, cuando tu aspirante se inscriba, '
                          'administración habilitará tu bonificación.',
                          style: TextStyle(color: cessumMuted(context), fontSize: 13),
                        ),
                      )
                    else
                      ..._referidos.map(_itemReferido),
                    const SizedBox(height: 24),
                  ],
                ),
    );
  }

  Widget _comoFunciona() {
    Widget paso(IconData ic, String t) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(ic, color: cessumGold, size: 20),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(t,
                      style: const TextStyle(fontSize: 13.5, height: 1.3))),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('¿Cómo funciona?',
              style:
                  TextStyle(fontWeight: FontWeight.w800, color: cessumRed)),
          const SizedBox(height: 6),
          paso(Icons.share_outlined,
              'Comparte tu código con quien quiera estudiar en CESSUM.'),
          paso(Icons.school_outlined,
              'Tu aspirante presenta el código al inscribirse y obtiene '
              '\$$_descAspirante de descuento en su inscripción.'),
          paso(Icons.verified_outlined,
              'Cuando administración verifique su inscripción, se habilita tu '
              'bonificación de \$$_bonoAlumno para tu próxima colegiatura.'),
        ],
      ),
    );
  }

  Widget _itemReferido(Map<String, dynamic> r) {
    final estatus = (r['estatus'] ?? 'Pendiente').toString();
    final aprobado = estatus.toLowerCase() == 'aprobado';
    final bono = r['bono'] is int ? r['bono'] as int : int.tryParse('${r['bono']}') ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text((r['aspirante'] ?? '').toString(),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text((r['fecha'] ?? '').toString(),
                    style:
                        const TextStyle(fontSize: 11.5, color: Colors.black45)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: aprobado
                  ? const Color(0xFF1E8E3E).withValues(alpha: 0.12)
                  : cessumGold.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              aprobado ? 'Aprobado +\$$bono' : 'Pendiente',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: aprobado ? const Color(0xFF1E8E3E) : cessumGold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

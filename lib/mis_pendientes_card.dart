import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart'
    show guardianUrl, CapturaCalificacionesScreen;
import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';
import 'mi_contrato_screen.dart';
import 'banners_semanales_screen.dart';
import 'mis_actas_docente_screen.dart';

/// Recuadro "Mis pendientes" para el panel del docente: junta en un solo lugar
/// lo que el profesor tiene por hacer (captura, contratos) con accesos directos.
class MisPendientesCard extends StatefulWidget {
  const MisPendientesCard({super.key});

  @override
  State<MisPendientesCard> createState() => _MisPendientesCardState();
}

class _MisPendientesCardState extends State<MisPendientesCard> {
  static const Color _verde = Color(0xFF1E8E3E);

  bool _cargando = true;
  bool _error = false;
  int _captura = 0;
  int _contratos = 0;
  int _actasDevueltas = 0;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final correo = (await SessionStore.validEmail()) ?? '';
      if (correo.isEmpty) {
        if (mounted) setState(() => _cargando = false);
        return;
      }
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'docente_pendientes',
        'correo': correo,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] == true) {
        setState(() {
          _captura = (data['capturaPendiente'] ?? 0) as int;
          _contratos = (data['contratosFaltan'] ?? 0) as int;
          _actasDevueltas = (data['actasDevueltas'] ?? 0) as int;
          _cargando = false;
        });
      } else {
        setState(() {
          _error = true;
          _cargando = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = true;
        _cargando = false;
      });
    }
  }

  void _abrir(Widget p) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => p));
  }

  @override
  Widget build(BuildContext context) {
    // Si no hay datos o hubo error, no estorbamos el panel.
    if (_error) return const SizedBox.shrink();

    final isDark = cessumIsDark(context);
    final totalPend = _captura + _contratos + _actasDevueltas;
    final alDia = !_cargando && totalPend == 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF211F1D) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: alDia
              ? _verde.withValues(alpha: 0.30)
              : cessumRed.withValues(alpha: 0.30),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(alDia ? Icons.verified_outlined : Icons.checklist_rtl,
                  color: alDia ? _verde : cessumRed, size: 22),
              const SizedBox(width: 8),
              Text('Mis pendientes',
                  style: CessumType.heading(16, color: cessumInk(context))),
              const Spacer(),
              if (_cargando)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (_cargando)
            Text('Revisando lo que tienes por hacer…',
                style: CessumType.body(13, color: cessumMuted(context)))
          else if (alDia)
            Text('¡Todo al día! No tienes pendientes por ahora.',
                style: CessumType.body(13, color: cessumMuted(context)))
          else ...[
            if (_captura > 0)
              _fila(
                icono: Icons.edit_note,
                texto: _captura == 1
                    ? '1 grupo por capturar'
                    : '$_captura grupos por capturar',
                onTap: () => _abrir(const CapturaCalificacionesScreen()),
              ),
            if (_contratos > 0)
              _fila(
                icono: Icons.assignment_late_outlined,
                texto: _contratos == 1
                    ? '1 materia sin contrato'
                    : '$_contratos materias sin contrato',
                onTap: () => _abrir(const MiContratoScreen()),
              ),
            if (_actasDevueltas > 0)
              _fila(
                icono: Icons.assignment_returned,
                texto: _actasDevueltas == 1
                    ? '1 acta devuelta por corregir'
                    : '$_actasDevueltas actas devueltas por corregir',
                onTap: () => _abrir(const MisActasDocenteScreen()),
              ),
          ],
          const Divider(height: 22),
          _fila(
            icono: Icons.image_outlined,
            texto: 'Descargar banners de mis materias',
            onTap: () => _abrir(const BannersSemanalesScreen()),
            tenue: true,
          ),
        ],
      ),
    );
  }

  Widget _fila({
    required IconData icono,
    required String texto,
    required VoidCallback onTap,
    bool tenue = false,
  }) {
    final color = tenue ? cessumGold : cessumRed;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(icono, size: 18, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(texto,
                  style: CessumType.body(14, color: cessumInk(context))),
            ),
            Icon(Icons.chevron_right, size: 20, color: cessumMuted(context)),
          ],
        ),
      ),
    );
  }
}

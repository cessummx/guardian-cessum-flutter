import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

/// Panel del ADMIN para gestionar las solicitudes de corrección que mandan
/// los docentes. Puede aprobar (aplica el cambio) o rechazar (no lo aplica).
class SolicitudesCorreccionScreen extends StatefulWidget {
  const SolicitudesCorreccionScreen({super.key});

  @override
  State<SolicitudesCorreccionScreen> createState() =>
      _SolicitudesCorreccionScreenState();
}

class _Solicitud {
  final String id;
  final String programa;
  final String generacion;
  final String grupo;
  final String materia;
  final String matricula;
  final String nombre;
  final String calActual;
  final String calPropuesta;
  final String motivo;
  final String docente;
  final String estado;
  const _Solicitud({
    required this.id,
    required this.programa,
    required this.generacion,
    required this.grupo,
    required this.materia,
    required this.matricula,
    required this.nombre,
    required this.calActual,
    required this.calPropuesta,
    required this.motivo,
    required this.docente,
    required this.estado,
  });
}

class _SolicitudesCorreccionScreenState
    extends State<SolicitudesCorreccionScreen> {
  List<_Solicitud> _solicitudes = [];
  bool _cargando = true;
  String? _error;

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
      final uri = Uri.parse(guardianUrl)
          .replace(queryParameters: {'accion': 'listar_solicitudes'});
      final resp = await http.get(uri).timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) {
        throw Exception(data['error'] ?? 'Respuesta inválida');
      }
      final lista = (data['solicitudes'] as List<dynamic>? ?? []);
      final sols = lista.map((e) {
        final m = e as Map<String, dynamic>;
        return _Solicitud(
          id: (m['id'] ?? '').toString(),
          programa: (m['programa'] ?? '').toString(),
          generacion: (m['generacion'] ?? '').toString(),
          grupo: (m['grupo'] ?? '').toString(),
          materia: (m['materia'] ?? '').toString(),
          matricula: (m['matricula'] ?? '').toString(),
          nombre: (m['nombre'] ?? '').toString(),
          calActual: (m['calificacionActual'] ?? '').toString(),
          calPropuesta: (m['calificacionPropuesta'] ?? '').toString(),
          motivo: (m['motivo'] ?? '').toString(),
          docente: (m['docente'] ?? '').toString(),
          estado: (m['estado'] ?? '').toString(),
        );
      }).toList();
      if (mounted) {
        setState(() {
          _solicitudes = sols;
          _cargando = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _cargando = false;
          _error =
              'No se pudieron cargar las solicitudes. Revisa tu conexión.';
        });
      }
    }
  }

  Future<void> _resolver(_Solicitud s, bool aprobar) async {
    final accionTxt = aprobar ? 'aprobar' : 'rechazar';
    String calCorregida = s.calPropuesta.trim();
    if (aprobar) {
      final ctrl = TextEditingController(text: calCorregida);
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Aprobar corrección'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Alumno: ${s.nombre}\nMateria: ${s.materia}\n'
                'Calificación actual: '
                '${s.calActual.trim().isEmpty ? '—' : s.calActual}',
                style: const TextStyle(height: 1.4),
              ),
              const SizedBox(height: 12),
              const Text('Calificación corregida (6 a 10):',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              TextField(
                controller: ctrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  hintText: 'Ej. 9',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Se actualizará la calificación y el progreso del alumno.',
                style: TextStyle(fontSize: 12, color: cessumMuted(context)),
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
                backgroundColor: const Color(0xFF1E8E3E),
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Aprobar'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      calCorregida = ctrl.text.trim().replaceAll(',', '.');
      final v = double.tryParse(calCorregida);
      if (v == null || v < 6 || v > 10) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Indica una calificación válida entre 6 y 10.'),
            backgroundColor: cessumRed,
          ));
        }
        return;
      }
    } else {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Rechazar corrección'),
          content: const Text(
            '¿Rechazar esta solicitud? No se hará ningún cambio en la '
            'calificación.',
            style: TextStyle(height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Rechazar'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    if (!mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          const Center(child: CircularProgressIndicator(color: cessumRed)),
    );

    try {
      final params = <String, String>{
        'accion': aprobar ? 'aprobar_solicitud' : 'rechazar_solicitud',
        'id': s.id,
      };
      if (aprobar) params['calificacion'] = calCorregida;
      final uri = Uri.parse(guardianUrl).replace(queryParameters: params);
      final resp = await http.get(uri).timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      Navigator.pop(context); // cerrar indicador

      if (data['ok'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(aprobar
                ? 'Corrección aprobada y aplicada.'
                : 'Solicitud rechazada.'),
            backgroundColor:
                aprobar ? const Color(0xFF1E8E3E) : cessumRed,
          ),
        );
        _cargar();
      } else {
        throw Exception(data['error'] ?? 'No se pudo $accionTxt');
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: cessumRed),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Solicitudes de corrección'),
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
              : _solicitudes.isEmpty
                  ? _vistaVacia()
                  : _vistaLista(),
    );
  }

  Widget _vistaLista() {
    return RefreshIndicator(
      color: cessumRed,
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12, left: 4),
            child: Text(
              '${_solicitudes.length} solicitud(es) pendiente(s).',
              style: TextStyle(fontSize: 13, color: cessumMuted(context)),
            ),
          ),
          ..._solicitudes.map(_tarjeta),
        ],
      ),
    );
  }

  Widget _tarjeta(_Solicitud s) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.nombre,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: cessumInk(context),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Matrícula: ${s.matricula}',
            style: TextStyle(fontSize: 12, color: cessumFaint(context)),
          ),
          const SizedBox(height: 10),
          _renglon(Icons.menu_book, s.materia),
          _renglon(Icons.school_outlined,
              '${s.programa} • Gen. ${s.generacion} • Grupo ${s.grupo}'),
          if (s.docente.isNotEmpty)
            _renglon(Icons.person_outline, 'Solicita: ${s.docente}'),
          const SizedBox(height: 10),
          // Cambio de calificación: actual -> propuesta
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFB8842C).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Column(
                  children: [
                    Text('Actual',
                        style: TextStyle(fontSize: 11, color: cessumFaint(context))),
                    Text(
                      s.calActual.isEmpty ? '—' : s.calActual,
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: cessumMuted(context)),
                    ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Icon(Icons.arrow_forward, color: Color(0xFFB8842C)),
                ),
                Column(
                  children: [
                    Text('Propuesta',
                        style: TextStyle(fontSize: 11, color: cessumFaint(context))),
                    Text(
                      s.calPropuesta.isEmpty ? '—' : s.calPropuesta,
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E8E3E)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (s.motivo.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Motivo:',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: cessumMuted(context))),
            const SizedBox(height: 2),
            Text(
              s.motivo,
              style: TextStyle(
                  fontSize: 13, color: cessumInk(context), height: 1.3),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: cessumRed,
                    side: const BorderSide(color: cessumRed),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  onPressed: () => _resolver(s, false),
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Rechazar'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E8E3E),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  onPressed: () => _resolver(s, true),
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Aprobar'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: cessumRed,
                side: const BorderSide(color: cessumRed),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              onPressed: () => _aplicarPerfil(s),
              icon: const Icon(Icons.badge_outlined, size: 18),
              label: const Text('Aplicar cambio de datos (perfil)'),
            ),
          ),
        ],
      ),
    );
  }

  String _valorSugerido(String motivo) {
    final m = RegExp(r'[Vv]alor correcto solicitado:\s*(.+)').firstMatch(motivo);
    if (m != null) {
      return m.group(1)!.split(RegExp(r'[\n.]')).first.trim();
    }
    return '';
  }

  Future<void> _aplicarPerfil(_Solicitud s) async {
    String campo = 'nombre';
    final valorCtrl =
        TextEditingController(text: _valorSugerido(s.motivo));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Aplicar cambio de datos'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Alumno: ${s.nombre}\nMatrícula: ${s.matricula}',
                    style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: campo,
                  decoration: const InputDecoration(
                      labelText: 'Dato a cambiar',
                      border: OutlineInputBorder(),
                      isDense: true),
                  items: const [
                    DropdownMenuItem(value: 'nombre', child: Text('Nombre')),
                    DropdownMenuItem(value: 'correo', child: Text('Correo')),
                    DropdownMenuItem(
                        value: 'programa', child: Text('Programa')),
                    DropdownMenuItem(
                        value: 'generacion', child: Text('Generación')),
                  ],
                  onChanged: (v) => setLocal(() => campo = v ?? 'nombre'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: valorCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Valor correcto',
                      border: OutlineInputBorder(),
                      isDense: true),
                ),
                const SizedBox(height: 8),
                Text(
                    'Se corregirá en toda la base: actas, boletas y credenciales.',
                    style: TextStyle(fontSize: 11, color: cessumMuted(context))),
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
                if (valorCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx, true);
              },
              child: const Text('Aplicar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final valor = valorCtrl.text.trim();
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          const Center(child: CircularProgressIndicator(color: cessumRed)),
    );
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'perfil_cambiar_dato',
        'matricula': s.matricula,
        'campo': campo,
        'valor': valor,
        'aplicar': '1',
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      Navigator.pop(context);
      if (data['ok'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Cambio aplicado en ${data['totalCeldas'] ?? 0} lugar(es). Se refleja en todos los documentos.'),
          backgroundColor: const Color(0xFF1E8E3E),
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('No se pudo: ${data['error'] ?? ''}'),
            backgroundColor: cessumRed));
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: cessumRed));
    }
  }

  Widget _renglon(IconData icon, String texto) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: cessumFaint(context)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(
                  fontSize: 13, color: cessumMuted(context), height: 1.3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _vistaVacia() {
    return RefreshIndicator(
      color: cessumRed,
      onRefresh: _cargar,
      child: ListView(
        children: [
          const SizedBox(height: 80),
          Icon(Icons.inbox_outlined, color: cessumFaint(context), size: 48),
          const SizedBox(height: 12),
          Text(
            'No hay solicitudes de corrección pendientes.',
            textAlign: TextAlign.center,
            style: TextStyle(color: cessumMuted(context), height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _vistaError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off, color: cessumFaint(context), size: 48),
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: cessumMuted(context), height: 1.4),
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
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'helpers.dart';

/// Genera de un golpe las constancias de toda una generación, cada una con
/// su folio, firma, sello y QR, en una carpeta de Drive lista para descargar.
class ConstanciasLoteScreen extends StatefulWidget {
  const ConstanciasLoteScreen({super.key});

  @override
  State<ConstanciasLoteScreen> createState() => _ConstanciasLoteScreenState();
}

class _ConstanciasLoteScreenState extends State<ConstanciasLoteScreen> {
  List<Map<String, dynamic>> _generaciones = [];
  Map<String, dynamic>? _sel;
  final _semestre = TextEditingController();
  bool _firmar = true;
  bool _cargando = true;
  bool _generando = false;
  String? _error;
  Map<String, dynamic>? _resultado;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _semestre.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final resp = await http
          .get(Uri.parse('$guardianUrl?accion=generaciones_lista'))
          .timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (!mounted) return;
      setState(() {
        _generaciones = (data['generaciones'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudieron cargar las generaciones.';
      });
    }
  }

  Future<void> _generar() async {
    final s = _sel;
    if (s == null) {
      _aviso('Selecciona una generación.');
      return;
    }
    final confirma = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Generar constancias'),
        content: Text(
            'Se generarán ${s['alumnos']} constancias de ${s['programa']} (${s['generacion']})'
            '${_firmar ? ', firmadas y selladas' : ', sin firma'}. Puede tardar un par de minutos. ¿Continuar?'),
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
    if (confirma != true) return;
    setState(() {
      _generando = true;
      _resultado = null;
    });
    try {
      final payload = {
        'accion': 'constancias_lote',
        'programa': s['programa'],
        'generacion': s['generacion'],
        'semestreTexto': _semestre.text.trim(),
        'firmar': _firmar,
      };
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode(payload))
          .timeout(const Duration(seconds: 600));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (!mounted) return;
      setState(() {
        _generando = false;
        _resultado = data;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _generando = false);
      _aviso('No se pudo generar: $e');
    }
  }

  void _aviso(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: Colors.redAccent,
      content: Text(m),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Constancias por lote',
            style: TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!),
                      const SizedBox(height: 8),
                      TextButton(
                          onPressed: _cargar,
                          child: const Text('Reintentar')),
                    ],
                  ),
                )
              : _resultado != null
                  ? _vistaResultado()
                  : _vistaFormulario(),
    );
  }

  Widget _vistaFormulario() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Selecciona una generación y genera todas sus constancias de una '
          'sola vez. Cada una sale con folio, código QR de verificación y, '
          'si lo activas, firma del Rector y sello institucional.',
          style: TextStyle(fontSize: 12.5, color: Colors.black54, height: 1.5),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<Map<String, dynamic>>(
          value: _sel,
          isExpanded: true,
          hint: const Text('Generación a procesar'),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            filled: true,
            fillColor: Colors.white,
            isDense: true,
          ),
          items: _generaciones
              .map((g) => DropdownMenuItem(
                    value: g,
                    child: Text(
                      '${g['programa']} · ${g['generacion']} (${g['alumnos']})',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ))
              .toList(),
          onChanged: (v) => setState(() => _sel = v),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _semestre,
          decoration: const InputDecoration(
            labelText: 'Texto de periodo/semestre (opcional)',
            hintText: 'Ej. cuatrimestre enero-abril 2026',
            border: OutlineInputBorder(),
            filled: true,
            fillColor: Colors.white,
            isDense: true,
          ),
        ),
        const SizedBox(height: 4),
        SwitchListTile(
          value: _firmar,
          activeColor: cessumRed,
          contentPadding: EdgeInsets.zero,
          title: const Text('Firmar y sellar',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
          subtitle: const Text(
              'Incluye firma del Rector y sello institucional en cada constancia.',
              style: TextStyle(fontSize: 11.5)),
          onChanged: (v) => setState(() => _firmar = v),
        ),
        const SizedBox(height: 12),
        if (_generando)
          Column(
            children: const [
              LinearProgressIndicator(color: cessumRed),
              SizedBox(height: 10),
              Text('Generando constancias... no cierres esta pantalla.',
                  style: TextStyle(fontSize: 12, color: Colors.black54)),
            ],
          )
        else
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
              onPressed: _generar,
              icon: const Icon(Icons.library_books),
              label: const Text('Generar constancias'),
            ),
          ),
        const SizedBox(height: 12),
        const Text(
          'Por seguridad del servidor, cada lote procesa hasta 40 alumnos. '
          'Si la generación es mayor, vuelve a ejecutar para el resto.',
          style: TextStyle(fontSize: 11, color: Colors.black45, height: 1.4),
        ),
      ],
    );
  }

  Widget _vistaResultado() {
    final r = _resultado!;
    final lista = (r['lista'] as List?) ?? [];
    final conError = lista.where((e) => e['folio'] == 'ERROR').length;
    // Nunca mostrar "null": si el backend no manda 'generadas',
    // usamos el conteo real de la lista (sin las que dieron error).
    final generadas = (r['generadas'] is num)
        ? (r['generadas'] as num).toInt()
        : (lista.length - conError);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF1E8E3E).withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
            border:
                Border.all(color: const Color(0xFF1E8E3E).withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('✓ $generadas constancias generadas',
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1E8E3E))),
              if (conError > 0)
                Text('$conError con error (revisa la lista)',
                    style: const TextStyle(fontSize: 12, color: cessumRed)),
              if (r['truncado'] == true)
                Text(
                    'Se procesaron las primeras ${r['tope']}. Ejecuta de nuevo para el resto.',
                    style: const TextStyle(fontSize: 12, color: cessumGold)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (((r['carpeta'] ?? '') as String).isNotEmpty)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: cessumGold,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () =>
                  Helpers.abrirUrlExterna((r['carpeta'] ?? '') as String, context),
              icon: const Icon(Icons.folder_open),
              label: const Text('Abrir carpeta en Drive (todas)'),
            ),
          ),
        const SizedBox(height: 16),
        const Text('Detalle',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        ...lista.map((raw) {
          final e = Map<String, dynamic>.from(raw as Map);
          final ok = e['folio'] != 'ERROR';
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            child: ListTile(
              dense: true,
              leading: Icon(ok ? Icons.check_circle : Icons.error,
                  color: ok ? const Color(0xFF1E8E3E) : cessumRed),
              title: Text('${e['nombre']} (${e['matricula']})',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
              subtitle: Text(ok ? 'Folio ${e['folio']}' : 'No se pudo generar',
                  style: const TextStyle(fontSize: 11.5)),
              trailing: ok
                  ? IconButton(
                      icon: const Icon(Icons.picture_as_pdf,
                          color: cessumRed),
                      onPressed: () => Helpers.abrirUrlExterna(
                          (e['pdf'] ?? '') as String, context),
                    )
                  : null,
            ),
          );
        }),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: () => setState(() => _resultado = null),
          icon: const Icon(Icons.arrow_back, color: cessumRed),
          label: const Text('Generar otra generación',
              style: TextStyle(color: cessumRed)),
        ),
      ],
    );
  }
}

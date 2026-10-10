import 'dart:convert';

import 'fecha_esp.dart';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'helpers.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

/// Tablero de contratos (admin): contadores por estatus, lista filtrable
/// y exportación a Excel (CSV) que genera el Guardián en Drive.
class ContratosTableroScreen extends StatefulWidget {
  const ContratosTableroScreen({super.key});

  @override
  State<ContratosTableroScreen> createState() => _ContratosTableroScreenState();
}

class _Contrato {
  final String folio;
  final String correo;
  final String nombre;
  final String tipo;
  final String pdfUrl;
  final String fecha;
  final String estatus;
  final String validadoPor;
  final String fechaValidacion;
  final String motivo;

  _Contrato({
    required this.folio,
    required this.correo,
    required this.nombre,
    required this.tipo,
    required this.pdfUrl,
    required this.fecha,
    required this.estatus,
    required this.validadoPor,
    required this.fechaValidacion,
    required this.motivo,
  });

  factory _Contrato.fromJson(Map<String, dynamic> j) {
    String s(dynamic v) => (v ?? '').toString().trim();
    return _Contrato(
      folio: s(j['folio']),
      correo: s(j['correo']),
      nombre: s(j['nombre']),
      tipo: s(j['tipo']),
      pdfUrl: s(j['pdfUrl']),
      fecha: s(j['fecha']),
      estatus: s(j['estatus']),
      validadoPor: s(j['validadoPor']),
      fechaValidacion: s(j['fechaValidacion']),
      motivo: s(j['motivo']),
    );
  }
}

class _ContratosTableroScreenState extends State<ContratosTableroScreen> {
  bool _cargando = true;
  bool _exportando = false;
  String _error = '';
  int _total = 0;
  int _pend = 0;
  int _val = 0;
  int _rech = 0;
  List<_Contrato> _contratos = [];
  String _filtro = 'Todos';
  String _busqueda = '';

  static const Color _verde = Color(0xFF1E8E3E);

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
      final uri = Uri.parse('$guardianUrl?accion=contratos_resumen');
      final resp = await http.get(uri).timeout(const Duration(seconds: 40));
      if (resp.statusCode != 200) {
        throw Exception('Error de conexión (${resp.statusCode}).');
      }
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) {
        throw Exception((data['error'] ?? 'No se pudo cargar.').toString());
      }
      final lista = (data['contratos'] as List? ?? [])
          .map((e) => _Contrato.fromJson(e as Map<String, dynamic>))
          .toList();
      if (!mounted) return;
      setState(() {
        _total = (data['total'] ?? lista.length) as int;
        _pend = (data['pendientes'] ?? 0) as int;
        _val = (data['validados'] ?? 0) as int;
        _rech = (data['rechazados'] ?? 0) as int;
        _contratos = lista;
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No pudimos cargar los contratos. Revisa tu conexión.';
      });
    }
  }

  List<_Contrato> get _filtrados {
    final q = _busqueda.trim().toLowerCase();
    return _contratos.where((c) {
      if (_filtro != 'Todos' && c.estatus != _filtro) return false;
      if (q.isEmpty) return true;
      return c.nombre.toLowerCase().contains(q) ||
          c.correo.toLowerCase().contains(q) ||
          c.folio.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _exportar() async {
    setState(() => _exportando = true);
    try {
      final uri = Uri.parse('$guardianUrl?accion=contratos_exportar');
      final resp = await http.get(uri).timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] == true && (data['url'] ?? '').toString().isNotEmpty) {
        if (!mounted) return;
        Helpers.abrirUrlExterna(data['url'].toString(), context);
      } else {
        throw Exception((data['error'] ?? 'No se pudo exportar.').toString());
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo generar el archivo.')),
        );
      }
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  Color _colorEstatus(String e) {
    if (e == 'Validado') return _verde;
    if (e == 'Rechazado') return cessumRed;
    return cessumGold;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Tablero de contratos'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _cargando ? null : _cargar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : _error.isNotEmpty
              ? _vistaError()
              : RefreshIndicator(
                  color: cessumRed,
                  onRefresh: _cargar,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    children: [
                      _contadores(),
                      const SizedBox(height: 14),
                      _botonExportar(),
                      const SizedBox(height: 16),
                      _buscador(),
                      const SizedBox(height: 10),
                      _chipsFiltro(),
                      const SizedBox(height: 12),
                      if (_filtrados.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 28),
                          child: Center(
                            child: Text(
                              'No hay contratos con ese filtro.',
                              style: TextStyle(color: cessumMuted(context)),
                            ),
                          ),
                        )
                      else
                        ..._filtrados.map(_tarjeta),
                    ],
                  ),
                ),
    );
  }

  Widget _contadores() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _tarjetaContador('Total', _total, cessumRed, Icons.description),
        _tarjetaContador('Pendientes', _pend, cessumGold, Icons.hourglass_bottom),
        _tarjetaContador('Validados', _val, _verde, Icons.verified),
        _tarjetaContador('Rechazados', _rech, Colors.redAccent, Icons.cancel),
      ],
    );
  }

  Widget _tarjetaContador(String titulo, int n, Color color, IconData icono) {
    final ancho = (MediaQuery.of(context).size.width - 16 * 2 - 12) / 2;
    return Container(
      width: ancho < 130 ? double.infinity : ancho,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          Icon(icono, color: color, size: 26),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$n',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              Text(
                titulo,
                style: TextStyle(fontSize: 12, color: cessumMuted(context)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _botonExportar() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: _verde,
          side: const BorderSide(color: _verde),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
        onPressed: _exportando ? null : _exportar,
        icon: _exportando
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: _verde),
              )
            : const Icon(Icons.table_view, size: 20),
        label: Text(_exportando ? 'Generando…' : 'Exportar a Excel'),
      ),
    );
  }

  Widget _buscador() {
    return TextField(
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Buscar nombre, correo o folio',
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

  Widget _chipsFiltro() {
    final opciones = ['Todos', 'Pendiente', 'Validado', 'Rechazado'];
    return Wrap(
      spacing: 8,
      children: [
        for (final o in opciones)
          ChoiceChip(
            label: Text(o),
            selected: _filtro == o,
            onSelected: (_) => setState(() => _filtro = o),
            selectedColor: cessumRed.withValues(alpha: 0.15),
            labelStyle: TextStyle(
              color: _filtro == o ? cessumRed : cessumMuted(context),
              fontWeight: _filtro == o ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
      ],
    );
  }

  Widget _tarjeta(_Contrato c) {
    final color = _colorEstatus(c.estatus);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: cessumIsDark(context) ? Colors.white12 : Colors.black12,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  c.nombre.isEmpty ? c.correo : c.nombre,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: cessumInk(context),
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  c.estatus,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${c.tipo}  ·  Folio ${c.folio}',
            style: TextStyle(fontSize: 12, color: cessumMuted(context)),
          ),
          if (c.fecha.isNotEmpty)
            Text(
              'Firmado: ${fechaEsp(c.fecha)}',
              style: TextStyle(fontSize: 12, color: cessumFaint(context)),
            ),
          if (c.estatus == 'Validado' && c.validadoPor.isNotEmpty)
            Text(
              'Validó: ${c.validadoPor}  ·  ${fechaEsp(c.fechaValidacion)}',
              style: TextStyle(fontSize: 12, color: cessumFaint(context)),
            ),
          if (c.estatus == 'Rechazado' && c.motivo.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Motivo: ${c.motivo}',
                style: TextStyle(
                    fontSize: 12,
                    color: cessumRed,
                    fontStyle: FontStyle.italic),
              ),
            ),
          if (c.pdfUrl.isNotEmpty) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: cessumRed,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => Helpers.abrirUrlExterna(c.pdfUrl, context),
                icon: const Icon(Icons.picture_as_pdf, size: 18),
                label: const Text('Ver PDF'),
              ),
            ),
          ],
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
}

// ===========================================================================
//  BANCO DE PLANEACIONES (8-oct-2026)
//  ---------------------------------------------------------------------------
//  Lista las planeaciones didácticas de CUALQUIER docente que ya fueron
//  VALIDADAS por Vicerrectoría, para que otro docente las tome como
//  referencia al planear su propio curso — el equivalente del ya existente
//  «Banco de presentaciones», pero para planeaciones.
//
//  Solo entran aquí las que tienen Estado = «validada» en la hoja
//  PlaneacionesEntrega (planea_banco, en Code.gs); un borrador o una
//  planeación «con observaciones» nunca aparece, para no exponer trabajo a
//  medias de otro docente. Abrir una entrada reutiliza exactamente el mismo
//  documento HTML que ya usa Planeación Didáctica (planeacion_documento.dart):
//  verla en una pestaña, descargarla en Word o guardarla como PDF.
// ===========================================================================
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'planeacion_documento.dart';

class BancoPlaneacionesScreen extends StatefulWidget {
  const BancoPlaneacionesScreen({super.key});
  @override
  State<BancoPlaneacionesScreen> createState() => _BancoPlaneacionesScreenState();
}

class _BancoPlaneacionesScreenState extends State<BancoPlaneacionesScreen> {
  bool _cargando = true;
  String _error = '';
  List<Map<String, dynamic>> _banco = [];
  String _filtroPrograma = '';
  final _filtro = TextEditingController();

  // Al abrir una entrada, mientras se lee del servidor.
  String? _abriendoId;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _filtro.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _comoListaMapas(dynamic l) {
    if (l is! List) return const [];
    final out = <Map<String, dynamic>>[];
    for (final x in l) {
      if (x is Map) out.add(Map<String, dynamic>.from(x));
    }
    return out;
  }

  Future<void> _cargar() async {
    setState(() { _cargando = true; _error = ''; });
    try {
      final r = await http
          .get(Uri.parse('$guardianUrl?accion=planea_banco'
              '&z=${DateTime.now().millisecondsSinceEpoch}'))
          .timeout(const Duration(seconds: 45));
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      if (j['ok'] != true) throw Exception(j['error'] ?? 'No se pudo cargar el banco.');
      if (!mounted) return;
      setState(() {
        _banco = _comoListaMapas(j['planeaciones']);
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = '$e'.replaceFirst('Exception: ', '');
      });
    }
  }

  List<String> get _programas {
    final set = <String>{};
    for (final b in _banco) {
      final p = '${b['programa'] ?? ''}'.trim();
      if (p.isNotEmpty) set.add(p);
    }
    final l = set.toList()..sort();
    return l;
  }

  List<Map<String, dynamic>> get _filtrado {
    final q = _filtro.text.trim().toLowerCase();
    return _banco.where((b) {
      if (_filtroPrograma.isNotEmpty &&
          '${b['programa'] ?? ''}'.trim() != _filtroPrograma) {
        return false;
      }
      if (q.isEmpty) return true;
      final heno = '${b['materia'] ?? ''} ${b['programa'] ?? ''} '
              '${b['generacion'] ?? ''} ${b['grupo'] ?? ''} ${b['docente'] ?? ''}'
          .toLowerCase();
      return q.split(RegExp(r'\s+')).every((w) => heno.contains(w));
    }).toList();
  }

  Future<void> _abrir(Map<String, dynamic> b, {required String accion}) async {
    final id = '${b['idPlaneacion'] ?? ''}';
    if (id.isEmpty) return;
    setState(() => _abriendoId = id);
    try {
      final r = await http
          .get(Uri.parse('$guardianUrl?accion=planea_banco_abrir&id=$id'
              '&z=${DateTime.now().millisecondsSinceEpoch}'))
          .timeout(const Duration(seconds: 45));
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      if (j['ok'] != true) throw Exception(j['error'] ?? 'No se pudo abrir esa planeación.');
      final contexto = Map<String, dynamic>.from((j['contexto'] as Map?) ?? {});
      final planeacion = Map<String, dynamic>.from((j['planeacion'] as Map?) ?? {});
      final cuerpo = documentoPlaneacion(
        contexto: contexto,
        planeacion: planeacion,
        docente: '${j['docente'] ?? ''}',
        modeloVersion: '${j['modeloVersion'] ?? ''}',
      );
      if (!mounted) return;
      switch (accion) {
        case 'ver':
          final abierta = abrirDocumento(cuerpo, contexto);
          if (!abierta && mounted) {
            _avisar('El navegador bloqueó la ventana. Permite las ventanas emergentes de app.cessum.mx '
                'y vuelve a intentarlo.');
          }
          break;
        case 'word':
          descargarWord(cuerpo, contexto);
          break;
        case 'pdf':
          final abierta = imprimirPdf(cuerpo, contexto);
          if (!abierta && mounted) {
            _avisar('El navegador bloqueó la ventana del PDF. Permite las ventanas emergentes de '
                'app.cessum.mx y vuelve a intentarlo.');
          }
          break;
      }
    } catch (e) {
      if (mounted) _avisar('$e'.replaceFirst('Exception: ', ''), esError: true);
    } finally {
      if (mounted) setState(() => _abriendoId = null);
    }
  }

  void _avisar(String msg, {bool esError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: esError ? cessumRed : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Banco de Planeaciones'),
      ),
      body: SafeArea(
        child: _cargando
            ? const Center(child: CircularProgressIndicator())
            : _error.isNotEmpty
                ? _errorView()
                : Column(children: [
                    _banner(),
                    _buscador(),
                    if (_programas.length > 1) _chipsPrograma(),
                    Expanded(child: _lista()),
                  ]),
      ),
    );
  }

  Widget _banner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFDF3E3),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cessumGold),
      ),
      child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.auto_stories_outlined, color: cessumGold),
        SizedBox(width: 10),
        Expanded(child: Text(
          'Planeaciones de otros docentes ya validadas por Vicerrectoría. Tómalas como '
          'referencia para la tuya en vez de empezar de cero.',
          style: TextStyle(fontSize: 12.5, height: 1.35),
        )),
      ]),
    );
  }

  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: _cargar, child: const Text('Reintentar')),
        ]),
      ),
    );
  }

  Widget _buscador() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: TextField(
        controller: _filtro,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: 'Buscar por materia, programa, generación, grupo o docente…',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _filtro.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => _filtro.clear()),
                ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          isDense: true,
        ),
      ),
    );
  }

  Widget _chipsPrograma() {
    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: const Text('Todos'),
              selected: _filtroPrograma.isEmpty,
              onSelected: (_) => setState(() => _filtroPrograma = ''),
            ),
          ),
          ..._programas.map((p) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(p),
                  selected: _filtroPrograma == p,
                  onSelected: (_) => setState(() => _filtroPrograma = p),
                ),
              )),
        ],
      ),
    );
  }

  Widget _lista() {
    final lista = _filtrado;
    if (lista.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _banco.isEmpty
                ? 'Todavía no hay planeaciones validadas en el banco.'
                : 'No hay planeaciones que coincidan con la búsqueda.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5, color: cessumMuted(context)),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
      itemCount: lista.length,
      itemBuilder: (_, i) {
        final b = lista[i];
        final id = '${b['idPlaneacion'] ?? ''}';
        final ocupado = _abriendoId == id;
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          color: cessumGold.withValues(alpha: 0.05),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${b['materia'] ?? ''}',
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(
                  '${b['programa'] ?? ''} · ${b['generacion'] ?? ''} · ${b['grupo'] ?? ''}'
                  '\nPor ${b['docente'] ?? 'otro docente'}'
                  '${'${b['dictaminada'] ?? ''}'.isNotEmpty ? ' · validada el ${b['dictaminada']}' : ''}',
                  style: const TextStyle(fontSize: 12.5)),
              const SizedBox(height: 6),
              if (ocupado)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Center(
                      child: SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))),
                )
              else
                Wrap(spacing: 4, children: [
                  TextButton.icon(
                    onPressed: () => _abrir(b, accion: 'ver'),
                    icon: const Icon(Icons.visibility_outlined, size: 18),
                    label: const Text('Ver'),
                  ),
                  TextButton.icon(
                    onPressed: () => _abrir(b, accion: 'word'),
                    icon: const Icon(Icons.description_outlined, size: 18),
                    label: const Text('Word'),
                  ),
                  TextButton.icon(
                    onPressed: () => _abrir(b, accion: 'pdf'),
                    icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                    label: const Text('PDF'),
                  ),
                ]),
            ]),
          ),
        );
      },
    );
  }
}

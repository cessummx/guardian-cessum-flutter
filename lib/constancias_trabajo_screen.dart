import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'helpers.dart';
import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

/// Constancias de trabajo (docente): lista las materias cuyo acta YA fue
/// validada y permite descargar la constancia oficial de cada una (PDF con
/// firma del Rector y sello). El backend calcula horas, periodo y modalidad.
class ConstanciasTrabajoScreen extends StatefulWidget {
  const ConstanciasTrabajoScreen({super.key});

  @override
  State<ConstanciasTrabajoScreen> createState() =>
      _ConstanciasTrabajoScreenState();
}

class _ConstanciasTrabajoScreenState extends State<ConstanciasTrabajoScreen> {
  bool _cargando = true;
  bool _error = false;
  String _correo = '';
  List<Map<String, dynamic>> _materias = [];

  // (9-sep) DESCARGAR TODAS EN UN ZIP.
  // Un botón que abriera una descarga por materia no habría funcionado: el
  // navegador bloquea abrir varias pestañas seguidas y se habrían perdido
  // todas menos la primera, sin avisar. El ZIP baja en un solo archivo y
  // cada constancia conserva su propio folio verificable.
  bool _zipando = false;
  String _zipAviso = '';

  // Clave de la materia que se está generando (para el spinner del botón).
  String? _generando;

  // Colores que responden al tema (sin alterar el modo claro).
  Color get _superficie => Theme.of(context).cardColor;
  Color get _textoFuerte => cessumIsDark(context) ? Colors.white : Colors.black87;
  Color get _textoSuave => cessumMuted(context);
  Color get _borde => cessumIsDark(context) ? Colors.white12 : Colors.black12;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  String _claveDe(Map<String, dynamic> m) {
    return '${m['programa']}||${m['generacion']}||${m['grupo']}||${m['materia']}';
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = false;
    });
    try {
      final correo = (await SessionStore.validEmail()) ?? '';
      _correo = correo;
      if (correo.isEmpty) {
        setState(() {
          _cargando = false;
          _error = true;
        });
        return;
      }
      final uri = Uri.parse('$guardianUrl?accion=constancias_listar'
          '&correo=${Uri.encodeComponent(correo)}');
      final resp = await http.get(uri).timeout(const Duration(seconds: 90));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception('error');
      if (!mounted) return;
      final lista = (data['materias'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      setState(() {
        _materias = lista;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = true;
      });
    }
  }

  Future<void> _descargar(Map<String, dynamic> m) async {
    if (_generando != null) return;
    setState(() => _generando = _claveDe(m));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Generando tu constancia…'),
    ));
    try {
      final uri = Uri.parse('$guardianUrl?accion=constancia_generar'
          '&correo=${Uri.encodeComponent(_correo)}'
          '&programa=${Uri.encodeComponent('${m['programa']}')}'
          '&generacion=${Uri.encodeComponent('${m['generacion']}')}'
          '&grupo=${Uri.encodeComponent('${m['grupo']}')}'
          '&materia=${Uri.encodeComponent('${m['materia']}')}');
      final resp = await http.get(uri).timeout(const Duration(seconds: 120));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() => _generando = null);
      if (data['ok'] == true && '${data['pdfUrl']}'.isNotEmpty) {
        await Helpers.abrirUrlExterna('${data['pdfUrl']}', context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              (data['error'] ?? 'No se pudo generar la constancia.').toString()),
          backgroundColor: cessumRed,
        ));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _generando = null);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error al generar: $e'),
        backgroundColor: cessumRed,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Constancias de trabajo',
            style: TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
              onPressed: _cargando ? null : _cargar,
              icon: const Icon(Icons.refresh)),
        ],
      ),
      body: RefreshIndicator(
        color: cessumRed,
        onRefresh: () async {
          await _cargar();
        },
        child: _cargando
            ? const _Centro(
                child: CircularProgressIndicator(color: cessumRed))
            : (_error
                ? _bannerError()
                : (_materias.isEmpty ? _vacio() : _lista())),
      ),
    );
  }

  Widget _botonTodas() {
    final n = _materias.length;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: (_zipando || n == 0) ? null : _descargarTodas,
        icon: _zipando
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: cessumRed))
            : const Icon(Icons.folder_zip_outlined, size: 20),
        label: Text(_zipando
            ? 'Generando las $n constancias…'
            : 'Descargar todas en un ZIP ($n)'),
        style: OutlinedButton.styleFrom(
          foregroundColor: cessumRed,
          side: const BorderSide(color: cessumRed),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }

  Future<void> _descargarTodas() async {
    // Se avisa ANTES de generar: cada constancia consume un folio oficial y
    // queda registrada. Que el docente sepa qué está disparando.
    final n = _materias.length;
    final seguir = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Generar todas tus constancias'),
        content: Text(
            'Se van a generar $n constancias y a empaquetar en un archivo ZIP.\n\n'
            'Cada una lleva su folio oficial y queda registrada, así que conviene '
            'hacerlo una sola vez. Puede tardar un par de minutos.'),
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
    if (seguir != true) return;

    setState(() { _zipando = true; _zipAviso = ''; });
    try {
      final uri = Uri.parse('$guardianUrl?accion=constancias_zip'
          '&correo=${Uri.encodeComponent(_correo)}&lento=1');
      // Son varios PDF armados uno por uno: la espera es de minutos, no de
      // segundos.
      final resp = await http.get(uri).timeout(const Duration(seconds: 300));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true || '${data['zipUrl']}'.isEmpty) {
        throw Exception(data['error'] ?? 'No se pudo generar el paquete.');
      }
      if (!mounted) return;
      setState(() {
        _zipando = false;
        // Lo que NO salió se dice, en vez de entregar un ZIP incompleto en
        // silencio.
        final fall = (data['fallidas'] as List?) ?? const [];
        final restan = int.tryParse('${data['restan'] ?? 0}') ?? 0;
        _zipAviso = '${data['total']} constancia(s) en el ZIP.'
            '${fall.isNotEmpty ? ' ${fall.length} no se pudo generar.' : ''}'
            '${restan > 0 ? ' Quedan $restan fuera; vuelve a intentarlo para esas.' : ''}';
      });
      await Helpers.abrirUrlExterna('${data['zipUrl']}', context);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _zipando = false;
        _zipAviso = 'No se pudo generar el paquete: '
            '${'$e'.replaceFirst('Exception: ', '')}';
      });
    }
  }

  Widget _lista() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(14),
      children: [
        _intro(),
        const SizedBox(height: 12),
        _botonTodas(),
        if (_zipAviso.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(_zipAviso,
              style: TextStyle(
                  fontSize: 11.5, height: 1.3, color: cessumMuted(context))),
        ],
        const SizedBox(height: 6),
        ..._materias.map(_tarjetaMateria),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _intro() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cessumRed, cessumRed.withValues(alpha: 0.78)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Tus constancias oficiales',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text(
            'Descarga la constancia de trabajo de cada materia con acta ya '
            'validada. Incluye periodo, horas y firma del Rector.',
            style: TextStyle(color: Colors.white70, fontSize: 12.5, height: 1.3),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaMateria(Map<String, dynamic> m) {
    final generando = _generando == _claveDe(m);
    final periodo = _periodoTexto(m);
    final horas = '${m['horas'] ?? ''}';
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _superficie,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borde),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${m['materia'] ?? ''}',
            style: TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
                color: _textoFuerte),
          ),
          const SizedBox(height: 4),
          Text(
            '${m['programa'] ?? ''}',
            style: TextStyle(fontSize: 12.5, color: _textoSuave, height: 1.25),
          ),
          if ('${m['generacionTxt'] ?? m['generacion'] ?? ''}'.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Generación ${m['generacionTxt'] ?? m['generacion']}'
                ' · Grupo ${m['grupo'] ?? ''}',
                style: TextStyle(fontSize: 12, color: _textoSuave),
              ),
            ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (periodo.isNotEmpty)
                _chip(Icons.event, periodo),
              if (horas.isNotEmpty)
                _chip(Icons.schedule, '$horas horas frente a grupo'),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11)),
                elevation: 1,
              ),
              onPressed: generando ? null : () => _descargar(m),
              icon: generando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.picture_as_pdf, size: 20),
              label: Text(
                generando ? 'Generando…' : 'Descargar constancia',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _periodoTexto(Map<String, dynamic> m) {
    final ini = '${m['inicioTxt'] ?? ''}'.trim();
    final fin = '${m['terminoTxt'] ?? ''}'.trim();
    if (ini.isEmpty && fin.isEmpty) return '';
    if (ini.isNotEmpty && fin.isNotEmpty) return '$ini al $fin';
    return ini.isNotEmpty ? ini : fin;
  }

  Widget _chip(IconData icono, String texto) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cessumGold.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cessumGold.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 14, color: cessumGold),
          const SizedBox(width: 6),
          Text(texto,
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: _textoFuerte)),
        ],
      ),
    );
  }

  Widget _vacio() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 60),
        Icon(Icons.workspace_premium_outlined,
            size: 64, color: cessumMuted(context)),
        const SizedBox(height: 16),
        Text(
          'Aún no tienes materias con acta validada.',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 15, fontWeight: FontWeight.w700, color: _textoFuerte),
        ),
        const SizedBox(height: 8),
        Text(
          'Cuando el acta de una de tus materias quede validada, aquí podrás '
          'descargar su constancia de trabajo.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: _textoSuave, height: 1.35),
        ),
      ],
    );
  }

  Widget _bannerError() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 40),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: cessumRed.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cessumRed.withValues(alpha: 0.30)),
          ),
          child: Row(
            children: [
              Icon(Icons.cloud_off, color: cessumRed, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'No se pudo cargar tu información. Revisa tu conexión.',
                  style: TextStyle(fontSize: 13, color: _textoFuerte),
                ),
              ),
              TextButton(
                onPressed: _cargando ? null : _cargar,
                style: TextButton.styleFrom(foregroundColor: cessumRed),
                child: const Text('Reintentar',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Centro extends StatelessWidget {
  final Widget child;
  const _Centro({required this.child});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: 400,
          child: Center(child: child),
        ),
      ],
    );
  }
}

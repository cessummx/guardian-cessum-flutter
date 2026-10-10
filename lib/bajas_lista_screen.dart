import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'helpers.dart';

/// Apartado de BAJAS para administración: ver todas las solicitudes (con su
/// tipo temporal/definitiva y motivo), validarlas o rechazarlas, corregir el
/// tipo/motivo, y registrar bajas a mano (las que ya venían del formulario).
class BajasListaScreen extends StatefulWidget {
  const BajasListaScreen({super.key});

  @override
  State<BajasListaScreen> createState() => _BajasListaScreenState();
}

const Color _verdeOk = Color(0xFF1E8E3E);
const List<String> _tipos = ['Temporal', 'Definitiva'];
const List<String> _motivos = [
  'Motivos académicos',
  'Motivos personales',
  'Motivos financieros',
  'Calidad de la enseñanza y plan de estudios',
  'Factores externos',
  'Otro',
];

class _Baja {
  final int fila;
  final String fecha;
  String estatus;
  final String nombre;
  final String matricula;
  final String correo;
  final String programa;
  final String generacion;
  final String tiempoCursando;
  String tipoBaja;
  String motivo;
  String comentarios;
  final String evidencia;
  final String validadaPor;
  final String fechaValidacion;
  // (25-sep) «Fuera de WhatsApp»: fecha · quién, o vacío si aún no se quita.
  String whatsapp;

  _Baja.fromMap(Map<String, dynamic> m)
      : fila = int.tryParse('${m['fila']}') ?? 0,
        fecha = (m['fecha'] ?? '').toString(),
        estatus = (m['estatus'] ?? '').toString(),
        nombre = (m['nombre'] ?? '').toString(),
        matricula = (m['matricula'] ?? '').toString(),
        correo = (m['correo'] ?? '').toString(),
        programa = (m['programa'] ?? '').toString(),
        generacion = (m['generacion'] ?? '').toString(),
        tiempoCursando = (m['tiempoCursando'] ?? '').toString(),
        tipoBaja = (m['tipoBaja'] ?? '').toString(),
        motivo = (m['motivo'] ?? '').toString(),
        comentarios = (m['comentarios'] ?? '').toString(),
        evidencia = (m['evidencia'] ?? '').toString(),
        validadaPor = (m['validadaPor'] ?? '').toString(),
        fechaValidacion = (m['fechaValidacion'] ?? '').toString(),
        whatsapp = (m['whatsapp'] ?? '').toString();
}

class _BajasListaScreenState extends State<BajasListaScreen> {
  bool _cargando = true;
  String? _error;
  List<_Baja> _items = [];
  final TextEditingController _busqueda = TextEditingController();
  // (25-sep) Filtro: bajas validadas que aún no se quitan de la base de WhatsApp.
  bool _soloPendWa = false;
  int get _pendWa => _items.where((b) => b.estatus == 'Validada' && b.whatsapp.isEmpty).length;

  List<_Baja> get _filtrados {
    final q = _busqueda.text.trim().toLowerCase();
    final base = _soloPendWa ? _items.where((b) => b.estatus == 'Validada' && b.whatsapp.isEmpty).toList() : _items;
    if (q.isEmpty) return base;
    return base.where((b) {
      return b.nombre.toLowerCase().contains(q) ||
          b.matricula.toLowerCase().contains(q) ||
          b.programa.toLowerCase().contains(q);
    }).toList();
  }

  @override
  void dispose() {
    _busqueda.dispose();
    super.dispose();
  }

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
          .replace(queryParameters: {'accion': 'bajas_listar'});
      final resp = await http.get(uri).timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      final lista = (data['bajas'] as List<dynamic>? ?? [])
          .map((e) => _Baja.fromMap(e as Map<String, dynamic>))
          .toList();
      if (mounted) {
        setState(() {
          _items = lista;
          _cargando = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _cargando = false;
          _error = 'No se pudo cargar. Revisa tu conexión.';
        });
      }
    }
  }

  Future<Map<String, dynamic>> _post(Map<String, dynamic> payload) async {
    final resp = await http
        .post(
          Uri.parse(guardianUrl),
          headers: {'Content-Type': 'text/plain;charset=utf-8'},
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 120));
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    if (data['ok'] != true || data.containsKey('guardadas')) {
      throw Exception(data['error'] ??
          'El Guardián todavía no tiene las funciones de bajas. Sube el '
              'Code.gs actualizado y publica una versión nueva.');
    }
    return data;
  }

  Future<void> _resolver(_Baja b, String estatus) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(estatus == 'Validada' ? 'Validar baja' : 'Rechazar baja'),
        content: Text(
          '¿${estatus == 'Validada' ? 'Validar' : 'Rechazar'} la baja de '
          '${b.nombre}?\n\nTipo: ${b.tipoBaja}\nMotivo: ${b.motivo}',
          style: const TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: estatus == 'Validada' ? _verdeOk : cessumRed,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(estatus == 'Validada' ? 'Validar' : 'Rechazar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _cargando = true);
    try {
      // (24-sep) Correo REAL: en «Ver como profesor» el de la vista es el del profesor.
      final correo = await SessionStore.realEmail();
      final data = await _post({
        'accion': 'baja_validar',
        'fila': b.fila,
        'matricula': b.matricula,
        'estatus': estatus,
        'validadaPor': correo ?? 'Administración',
      });
      _aviso(estatus == 'Validada' ? 'Baja validada.' : 'Baja rechazada.');
      await _cargar();
      final pdf = (data['pdf'] ?? '').toString();
      if (mounted && estatus == 'Validada' && pdf.isNotEmpty) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Constancia de baja'),
            content: const Text(
                'Se generó la constancia oficial de baja (con QR, firma del '
                'Rector y sello) y se envió al correo del alumno.'),
            actions: [
              TextButton(
                onPressed: () {
                  Helpers.abrirUrlExterna(pdf, context);
                  Navigator.pop(ctx);
                },
                child: const Text('Abrir constancia'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: cessumRed, foregroundColor: Colors.white),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Listo'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _cargando = false);
      _aviso('No se pudo guardar: $e');
    }
  }

  Future<void> _editarTipoMotivo(_Baja b) async {
    String tipo = _tipos.contains(b.tipoBaja) ? b.tipoBaja : _tipos.first;
    String motivo = _motivos.contains(b.motivo) ? b.motivo : _motivos.last;
    final comentarios = TextEditingController(text: b.comentarios);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Corregir baja'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: tipo,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: 'Tipo de baja', isDense: true),
                  items: _tipos
                      .map((t) =>
                          DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (v) => setLocal(() => tipo = v ?? tipo),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: motivo,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: 'Motivo', isDense: true),
                  items: _motivos
                      .map((t) =>
                          DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (v) => setLocal(() => motivo = v ?? motivo),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: comentarios,
                  maxLines: 3,
                  decoration: const InputDecoration(
                      labelText: 'Comentarios', border: OutlineInputBorder()),
                ),
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
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    setState(() => _cargando = true);
    try {
      await _post({
        'accion': 'baja_validar',
        'fila': b.fila,
        'matricula': b.matricula,
        'estatus': b.estatus.isEmpty ? 'Pendiente' : b.estatus,
        'tipoBaja': tipo,
        'motivo': motivo,
        'comentarios': comentarios.text.trim(),
      });
      _aviso('Baja actualizada.');
      await _cargar();
    } catch (e) {
      if (mounted) setState(() => _cargando = false);
      _aviso('No se pudo guardar: $e');
    }
  }

  Future<void> _registrar() async {
    final nombre = TextEditingController();
    final matricula = TextEditingController();
    final correo = TextEditingController();
    final programa = TextEditingController();
    final generacion = TextEditingController();
    final tiempo = TextEditingController();
    final comentarios = TextEditingController();
    String tipo = _tipos.first;
    String motivo = _motivos.first;
    String estatus = 'Validada';

    // Autocompletado EN VIVO: al escribir, muestra opciones; al tocar una, autollena.
    List<Map<String, dynamic>> sugerencias = [];
    Timer? debounce;

    void rellenar(
        Map<String, dynamic> sa, void Function(void Function()) setLocal) {
      setLocal(() {
        nombre.text = (sa['nombre'] ?? '').toString();
        matricula.text = (sa['matricula'] ?? '').toString();
        correo.text = (sa['correo'] ?? '').toString();
        programa.text = (sa['programa'] ?? '').toString();
        generacion.text = (sa['generacion'] ?? '').toString();
        sugerencias = [];
      });
    }

    void buscarVivo(String q, void Function(void Function()) setLocal) {
      debounce?.cancel();
      if (q.trim().length < 2) {
        setLocal(() => sugerencias = []);
        return;
      }
      debounce = Timer(const Duration(milliseconds: 350), () async {
        List<Map<String, dynamic>> ms = [];
        try {
          // GET (no POST): por GET el backend devuelve 'alumnos'.
          final uri = Uri.parse(guardianUrl).replace(
              queryParameters: {'accion': 'buscar_alumno', 'q': q.trim()});
          final r = await http.get(uri).timeout(const Duration(seconds: 20));
          final data = jsonDecode(r.body) as Map<String, dynamic>;
          if (data['ok'] == true) {
            ms = (((data['alumnos'] ?? data['resultados']) as List?) ?? [])
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
          }
        } catch (_) {}
        setLocal(() => sugerencias = ms);
      });
    }

    Widget campo(TextEditingController c, String etq) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: TextField(
            controller: c,
            decoration: InputDecoration(
                labelText: etq,
                border: const OutlineInputBorder(),
                isDense: true),
          ),
        );

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Registrar baja'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: TextField(
                    controller: nombre,
                    onChanged: (v) => buscarVivo(v, setLocal),
                    decoration: const InputDecoration(
                      labelText: 'Nombre del estudiante',
                      helperText: 'Escribe unas letras y elige de la lista',
                      border: OutlineInputBorder(),
                      isDense: true,
                      prefixIcon: Icon(Icons.search, color: cessumRed),
                    ),
                  ),
                ),
                if (sugerencias.isNotEmpty)
                  Container(
                    constraints: const BoxConstraints(maxHeight: 200),
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      border: Border.all(color: cessumRed.withOpacity(0.4)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: ListView(
                      shrinkWrap: true,
                      children: sugerencias
                          .map((m) => ListTile(
                                dense: true,
                                title: Text((m['nombre'] ?? '').toString(),
                                    style: const TextStyle(fontSize: 13)),
                                subtitle: Text(
                                    '${m['matricula'] ?? ''} · ${m['programa'] ?? ''} · ${m['generacion'] ?? ''}',
                                    style: const TextStyle(fontSize: 11)),
                                onTap: () => rellenar(m, setLocal),
                              ))
                          .toList(),
                    ),
                  ),
                campo(matricula, 'Matrícula'),
                campo(correo, 'Correo'),
                campo(programa, 'Programa'),
                campo(generacion, 'Generación'),
                campo(tiempo, 'Tiempo cursando'),
                DropdownButtonFormField<String>(
                  value: tipo,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: 'Tipo de baja', isDense: true),
                  items: _tipos
                      .map((t) =>
                          DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (v) => setLocal(() => tipo = v ?? tipo),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: motivo,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: 'Motivo', isDense: true),
                  items: _motivos
                      .map((t) =>
                          DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (v) => setLocal(() => motivo = v ?? motivo),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: comentarios,
                  maxLines: 3,
                  decoration: const InputDecoration(
                      labelText: 'Comentarios', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: estatus,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: 'Estatus', isDense: true),
                  items: const [
                    DropdownMenuItem(
                        value: 'Validada', child: Text('Validada')),
                    DropdownMenuItem(
                        value: 'Pendiente', child: Text('Pendiente')),
                  ],
                  onChanged: (v) => setLocal(() => estatus = v ?? estatus),
                ),
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
                if (nombre.text.trim().isEmpty ||
                    matricula.text.trim().isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                      content: Text('El nombre y la matrícula son obligatorios.')));
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('Registrar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    setState(() => _cargando = true);
    try {
      final quien = await SessionStore.realEmail();   // correo real (24-sep)
      await _post({
        'accion': 'baja_enviar',
        'nombre': nombre.text.trim(),
        'matricula': matricula.text.trim(),
        'correo': correo.text.trim(),
        'programa': programa.text.trim(),
        'generacion': generacion.text.trim(),
        'tiempoCursando': tiempo.text.trim(),
        'tipoBaja': tipo,
        'motivo': motivo,
        'comentarios': comentarios.text.trim(),
        'estatus': estatus,
        'validadaPor': quien ?? 'Administración',
      });
      _aviso('Baja registrada.');
      await _cargar();
    } catch (e) {
      if (mounted) setState(() => _cargando = false);
      _aviso('No se pudo registrar: $e');
    }
  }

  Future<void> _abrirEvidencia(String url) async {
    try {
      await launchUrl(Uri.parse(url), webOnlyWindowName: '_blank');
    } catch (_) {
      _aviso('No se pudo abrir la evidencia.');
    }
  }

  /// (25-sep) Marca (o desmarca) que el alumno YA se quitó de la base interna
  /// de recordatorios de WhatsApp. Esa base se actualiza a mano; esto deja
  /// constancia de quién lo hizo y cuándo.
  Future<void> _marcarWhatsapp(_Baja b, bool marcado) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(marcado ? '¿Ya se quitó de WhatsApp?' : '¿Desmarcar?', style: const TextStyle(fontSize: 17)),
        content: Text(marcado
            ? 'Confirme que ${b.nombre} YA fue quitado(a) de la base de recordatorios de WhatsApp. '
                'Quedará registrado con su nombre y la fecha.'
            : 'Se quitará la marca de «fuera de WhatsApp» de ${b.nombre}.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: marcado ? _verdeOk : cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(marcado ? 'Sí, ya se quitó' : 'Desmarcar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final data = await _post({'accion': 'baja_whatsapp_marcar', 'fila': b.fila, 'matricula': b.matricula, 'marcado': marcado});
      if (data['ok'] != true) throw Exception(data['error'] ?? 'No se pudo guardar.');
      setState(() => b.whatsapp = (data['whatsapp'] ?? '').toString());
      _aviso(marcado ? 'Registrado: ya está fuera de WhatsApp.' : 'Marca quitada.');
    } catch (e) {
      _aviso('$e'.replaceFirst('Exception: ', ''));
    }
  }

  Widget _bloqueWhatsapp(_Baja b) {
    if (b.whatsapp.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(children: [
          const Icon(Icons.check_circle, size: 18, color: _verdeOk),
          const SizedBox(width: 6),
          Expanded(
            child: Text('Fuera de WhatsApp · ${b.whatsapp}',
                style: const TextStyle(fontSize: 12.5, color: _verdeOk, fontWeight: FontWeight.w600)),
          ),
          TextButton(
            onPressed: () => _marcarWhatsapp(b, false),
            child: const Text('Deshacer', style: TextStyle(fontSize: 12)),
          ),
        ]),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: OutlinedButton.icon(
        onPressed: () => _marcarWhatsapp(b, true),
        icon: const Icon(Icons.phonelink_erase, size: 16, color: cessumGold),
        label: const Text('Ya se quitó de WhatsApp', style: TextStyle(color: cessumGold, fontSize: 13)),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: cessumGold),
          minimumSize: const Size(0, 34),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }

  void _aviso(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
    );
  }

  void _copiarExcel() {
    final b = StringBuffer();
    b.writeln('Fecha\tMatricula\tNombre\tPrograma\tGeneracion\t'
        'Estatus\tTipo\tMotivo\tComentarios\tValidadaPor');
    for (final x in _filtrados) {
      b.writeln('${x.fecha}\t${x.matricula}\t${x.nombre}\t${x.programa}\t'
          '${x.generacion}\t${x.estatus}\t${x.tipoBaja}\t${x.motivo}\t'
          '${x.comentarios.replaceAll('\n', ' ')}\t${x.validadaPor}');
    }
    Helpers.copiarAlPortapapeles(
        context, b.toString(), 'Bajas (${_filtrados.length})');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Bajas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.table_view),
            tooltip: 'Copiar para Excel',
            onPressed: (_cargando || _items.isEmpty) ? null : _copiarExcel,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _cargando ? null : _cargar,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        onPressed: _cargando ? null : _registrar,
        icon: const Icon(Icons.person_remove),
        label: const Text('Registrar baja'),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : _error != null
              ? _vistaError()
              : _items.isEmpty
                  ? _vistaVacia()
                  : Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                          child: TextField(
                            controller: _busqueda,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              hintText: 'Buscar por nombre, matrícula o programa',
                              prefixIcon: const Icon(Icons.search),
                              isDense: true,
                              suffixIcon: _busqueda.text.isEmpty
                                  ? null
                                  : IconButton(
                                      icon: const Icon(Icons.clear),
                                      onPressed: () => setState(
                                          () => _busqueda.clear()),
                                    ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                        // (25-sep) Pendientes de quitar de la base de WhatsApp.
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: FilterChip(
                              label: Text('Pendientes de quitar de WhatsApp ($_pendWa)'),
                              selected: _soloPendWa,
                              selectedColor: cessumGold.withValues(alpha: 0.2),
                              onSelected: (v) => setState(() => _soloPendWa = v),
                            ),
                          ),
                        ),
                        Expanded(
                          child: RefreshIndicator(
                            color: cessumRed,
                            onRefresh: _cargar,
                            child: _filtrados.isEmpty
                                ? ListView(
                                    children: [
                                      Padding(
                                        padding: EdgeInsets.all(40),
                                        child: Text(
                                          'Sin coincidencias.',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                              color: cessumMuted(context)),
                                        ),
                                      ),
                                    ],
                                  )
                                : ListView(
                                    padding: const EdgeInsets.fromLTRB(
                                        16, 8, 16, 90),
                                    children:
                                        _filtrados.map(_tarjeta).toList(),
                                  ),
                          ),
                        ),
                      ],
                    ),
    );
  }

  // ---- Contador de 72 horas HÁBILES (lun-vie) desde la solicitud de baja ----
  // Igual criterio que titulación e incidencias: solo cuentan días hábiles.
  static const int _kHorasBaja = 72;

  DateTime? _parseFechaBaja(String s) {
    s = s.trim();
    if (s.isEmpty) return null;
    final m1 = RegExp(r'(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(s);
    if (m1 != null) {
      return DateTime(int.parse(m1.group(1)!), int.parse(m1.group(2)!),
          int.parse(m1.group(3)!));
    }
    final m2 = RegExp(r'(\d{1,2})/(\d{1,2})/(\d{4})').firstMatch(s);
    if (m2 != null) {
      return DateTime(int.parse(m2.group(3)!), int.parse(m2.group(2)!),
          int.parse(m2.group(1)!));
    }
    const meses = {
      'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
      'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12
    };
    final m3 =
        RegExp(r'([A-Za-z]{3})[a-z]*\s+(\d{1,2})\s+(\d{4})').firstMatch(s);
    if (m3 != null) {
      final mes = meses[m3.group(1)!.toLowerCase()];
      if (mes != null) {
        return DateTime(
            int.parse(m3.group(3)!), mes, int.parse(m3.group(2)!));
      }
    }
    return null;
  }

  // Horas hábiles transcurridas entre dos fechas (excluye sáb y dom).
  double _horasHabiles(DateTime desde, DateTime hasta) {
    if (!hasta.isAfter(desde)) return 0;
    double horas = 0;
    var cursor = desde;
    while (cursor.isBefore(hasta)) {
      final sig = cursor.add(const Duration(hours: 1));
      final finTramo = sig.isBefore(hasta) ? sig : hasta;
      // cuenta la hora si el día es hábil (lun=1..vie=5)
      if (cursor.weekday >= 1 && cursor.weekday <= 5) {
        horas += finTramo.difference(cursor).inMinutes / 60.0;
      }
      cursor = sig;
    }
    return horas;
  }

  // Badge del timer. Solo para bajas PENDIENTES (las resueltas ya no cuentan).
  Widget _timerBaja(_Baja b) {
    if (b.estatus != 'Pendiente' && b.estatus.isNotEmpty) {
      return const SizedBox.shrink();
    }
    final ini = _parseFechaBaja(b.fecha);
    if (ini == null) return const SizedBox.shrink();
    final transcurridas = _horasHabiles(ini, DateTime.now());
    final restan = _kHorasBaja - transcurridas;
    final vencida = restan <= 0;
    final Color color;
    final String texto;
    if (vencida) {
      color = cessumRed;
      texto = 'Vencida (+${(-restan).toStringAsFixed(0)} h háb.)';
    } else if (restan <= 12) {
      color = cessumRed;
      texto = 'Faltan ${restan.toStringAsFixed(0)} h háb.';
    } else if (restan <= 24) {
      color = cessumGold;
      texto = 'Faltan ${restan.toStringAsFixed(0)} h háb.';
    } else {
      color = _verdeOk;
      texto = 'Faltan ${restan.toStringAsFixed(0)} h háb.';
    }
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(vencida ? Icons.alarm_off : Icons.alarm,
              size: 12, color: color),
          const SizedBox(width: 3),
          Text(texto,
              style: TextStyle(
                  fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }

  Widget _tarjeta(_Baja b) {
    final pendiente = b.estatus == 'Pendiente';
    final validada = b.estatus == 'Validada';
    final cEstatus =
        pendiente ? cessumGold : (validada ? _verdeOk : cessumRed);
    final defin = b.tipoBaja.toLowerCase().contains('defin');
    final cTipo = defin ? cessumRed : const Color(0xFF1565C0);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            color: cEstatus.withValues(alpha: 0.10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                Icon(
                    pendiente
                        ? Icons.hourglass_top
                        : (validada ? Icons.verified : Icons.cancel),
                    size: 16,
                    color: cEstatus),
                const SizedBox(width: 6),
                Text(b.estatus.isEmpty ? 'Pendiente' : b.estatus,
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: cEstatus,
                        fontSize: 13)),
                _timerBaja(b),
                const Spacer(),
                Text(b.fecha,
                    style: TextStyle(fontSize: 11, color: cessumFaint(context))),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(b.nombre,
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: cessumInk(context))),
                    ),
                    if (b.tipoBaja.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: cTipo.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(b.tipoBaja,
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: cTipo)),
                      ),
                  ],
                ),
                Text('Matrícula: ${b.matricula}',
                    style:
                        const TextStyle(fontSize: 12, color: Colors.black54)),
                const SizedBox(height: 8),
                _linea('Programa', b.programa),
                _linea('Generación', b.generacion),
                _linea('Tiempo cursando', b.tiempoCursando),
                _linea('Motivo', b.motivo),
                _linea('Comentarios', b.comentarios),
                if (b.correo.isNotEmpty) _linea('Correo', b.correo),
                if (!pendiente && b.validadaPor.isNotEmpty)
                  _linea('Resuelta por',
                      '${b.validadaPor} · ${b.fechaValidacion}'),
                // (25-sep) Constancia de que ya no le llegan recordatorios de WhatsApp.
                if (b.estatus == 'Validada') _bloqueWhatsapp(b),
                if (b.evidencia.isNotEmpty && b.evidencia.startsWith('http'))
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: OutlinedButton.icon(
                      onPressed: () => _abrirEvidencia(b.evidencia),
                      icon:
                          const Icon(Icons.description, size: 16, color: cessumRed),
                      label: const Text('Ver documento',
                          style: TextStyle(color: cessumRed, fontSize: 13)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: cessumRed),
                        minimumSize: const Size(0, 34),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ),
                const Divider(height: 22),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: () => _editarTipoMotivo(b),
                      icon: const Icon(Icons.edit, size: 16, color: cessumGold),
                      label: const Text('Corregir',
                          style: TextStyle(
                              color: Color(0xFF8A6418), fontSize: 13)),
                    ),
                    const Spacer(),
                    if (pendiente) ...[
                      OutlinedButton(
                        onPressed: () => _resolver(b, 'Rechazada'),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: cessumRed),
                          foregroundColor: cessumRed,
                        ),
                        child: const Text('Rechazar'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () => _resolver(b, 'Validada'),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: _verdeOk,
                            foregroundColor: Colors.white),
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('Validar'),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _linea(String etq, String valor) {
    if (valor.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text('$etq:',
                style: TextStyle(fontSize: 13, color: cessumMuted(context))),
          ),
          Expanded(
            child: Text(valor,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cessumInk(context))),
          ),
        ],
      ),
    );
  }

  Widget _vistaVacia() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox, color: cessumFaint(context), size: 52),
            SizedBox(height: 12),
            Text('No hay solicitudes de baja por ahora.',
                textAlign: TextAlign.center,
                style: TextStyle(color: cessumMuted(context))),
          ],
        ),
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
            Text(_error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: cessumMuted(context), height: 1.4)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed, foregroundColor: Colors.white),
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

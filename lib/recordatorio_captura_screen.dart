import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';

/// (ADMIN) Previsualiza qué docentes tienen captura de calificaciones pendiente
/// y les envía un recordatorio por correo, con su marca CESSUM.
class RecordatorioCapturaScreen extends StatefulWidget {
  const RecordatorioCapturaScreen({super.key});

  @override
  State<RecordatorioCapturaScreen> createState() =>
      _RecordatorioCapturaScreenState();
}

class _RecordatorioCapturaScreenState extends State<RecordatorioCapturaScreen> {
  List<Map<String, dynamic>> _docentes = [];
  int _totalMaterias = 0;
  bool _cargando = true;
  bool _enviando = false;
  String? _error;
  String? _resultado;
  final TextEditingController _fechaLimite = TextEditingController();
  bool? _autoActivo;
  bool _togglingAuto = false;

  @override
  void initState() {
    super.initState();
    _cargar();
    _cargarAuto();
  }

  Future<void> _cargarAuto() async {
    try {
      final correo = await _correo();
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'recordatorio_captura_trigger_estado',
        'correo': correo,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] == true) setState(() => _autoActivo = data['activo'] == true);
    } catch (_) {/* opcional: si falla, no mostramos el interruptor */}
  }

  Future<void> _toggleAuto(bool v) async {
    // (24-sep) Encenderlo deja correos AUTOMÁTICOS a los docentes cada semana:
    // se confirma diciendo cuándo y a cuántos les llegaría hoy. Apagarlo no envía nada.
    if (v) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Encender el recordatorio automático'),
          content: Text(
              'Desde ahora, CADA LUNES a las 8:00 a. m. se enviará un correo a cada docente '
              'que tenga captura pendiente en ese momento.\n\n'
              'Hoy le llegaría a ${_docentes.length} docente(s).\n\n'
              'Puede apagarlo cuando quiera con este mismo interruptor.',
              style: const TextStyle(fontSize: 13.5, height: 1.4)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: cessumRed),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Encender'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    if (mounted) setState(() => _togglingAuto = true);
    try {
      final correo = await _correo();
      final body = jsonEncode({
        'accion': 'recordatorio_captura_trigger_set',
        'correo': correo,
        'activar': v,
      });
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'}, body: body)
          .timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] == true) {
        setState(() => _autoActivo = data['activo'] == true);
      } else {
        setState(() => _resultado = 'No se pudo cambiar el envío automático.');
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _resultado = 'Error de conexión al cambiar el automático.');
    } finally {
      if (mounted) setState(() => _togglingAuto = false);
    }
  }

  @override
  void dispose() {
    _fechaLimite.dispose();
    super.dispose();
  }

  Future<String> _correo() async => (await SessionStore.realEmail()) ?? '';

  Future<void> _cargar() async {
    if (mounted) {
      setState(() {
        _cargando = true;
        _error = null;
        _resultado = null;
      });
    }
    try {
      final correo = await _correo();
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'recordatorio_captura_previa',
        'correo': correo,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'No autorizado');
      final lista = (data['docentes'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;
      setState(() {
        _docentes = lista;
        _totalMaterias = (data['totalMaterias'] ?? 0) as int;
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo cargar. ¿Tienes permiso de administrador?';
      });
    }
  }

  Future<void> _enviar() async {
    final n = _docentes.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enviar recordatorios'),
        content: Text(
            'Se enviará un correo de recordatorio a $n docente(s) con captura '
            'pendiente. ¿Deseas continuar?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: cessumRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sí, enviar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _ejecutar(simular: false);
  }

  Future<void> _ejecutar({required bool simular}) async {
    if (mounted) {
      setState(() {
        _enviando = true;
        _resultado = null;
      });
    }
    try {
      final correo = await _correo();
      final body = jsonEncode({
        'accion': 'recordatorio_captura_enviar',
        'correo': correo,
        'fechaLimite': _fechaLimite.text.trim(),
        'simular': simular,
      });
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'}, body: body)
          .timeout(const Duration(seconds: 90));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] == true) {
        final env = data['enviados'] ?? 0;
        final fal = data['fallidos'] ?? 0;
        setState(() {
          _resultado = simular
              ? 'Simulación: se enviarían $env correos.'
              : 'Listo: $env enviados${fal != 0 ? ', $fal con problema' : ''}.';
        });
      } else {
        setState(() => _resultado = 'Error: ${data['error'] ?? 'desconocido'}');
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _resultado = 'Error de conexión al enviar.');
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Recordatorio de captura'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: (_cargando || _enviando) ? null : _cargar,
          ),
        ],
      ),
      body: _cuerpo(),
    );
  }

  Widget _cuerpo() {
    if (_cargando) {
      return ListView(padding: const EdgeInsets.all(16), children: const [
        SkeletonCard(),
        SizedBox(height: 12),
        SkeletonCard(),
      ]);
    }
    if (_error != null) {
      return ListView(children: [
        const SizedBox(height: 80),
        CessumEmptyState(
          title: 'No se pudo cargar',
          subtitle: _error,
          icon: Icons.lock_outline,
          action: FilledButton.icon(
            onPressed: _cargar,
            style: FilledButton.styleFrom(backgroundColor: cessumRed),
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar'),
          ),
        ),
      ]);
    }
    if (_docentes.isEmpty) {
      return ListView(children: const [
        SizedBox(height: 80),
        CessumEmptyState(
          title: '¡Captura al día!',
          subtitle: 'Ningún docente tiene captura de calificaciones pendiente.',
          icon: Icons.verified_outlined,
        ),
      ]);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cessumRed.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cessumRed.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              Icon(Icons.mark_email_unread_outlined, color: cessumRed, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${_docentes.length} docente(s) con pendientes',
                        style:
                            CessumType.heading(16, color: cessumInk(context))),
                    const SizedBox(height: 2),
                    Text('$_totalMaterias materia(s) sin terminar de capturar',
                        style:
                            CessumType.body(13, color: cessumMuted(context))),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _fechaLimite,
          decoration: InputDecoration(
            labelText: 'Fecha límite (opcional)',
            helperText: 'Se incluye en el correo. Ej. 30 de junio de 2026.',
            isDense: true,
            border: const OutlineInputBorder(),
            focusedBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: cessumRed, width: 1.6),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _enviando ? null : () => _ejecutar(simular: true),
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('Simular'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: cessumRed),
                onPressed: _enviando ? null : _enviar,
                icon: _enviando
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send),
                label: const Text('Enviar a todos'),
              ),
            ),
          ],
        ),
        if (_autoActivo != null) ...[
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: cessumGold.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cessumGold.withValues(alpha: 0.30)),
            ),
            child: SwitchListTile(
              value: _autoActivo!,
              activeColor: cessumRed,
              onChanged: _togglingAuto ? null : _toggleAuto,
              title: Text('Enviar automáticamente cada lunes',
                  style: CessumType.body(14, color: cessumInk(context))),
              subtitle: Text(
                  _autoActivo!
                      ? 'Activo: los lunes a las 8:00 se avisa solo a quien tenga pendientes.'
                      : 'Apagado: solo se envía cuando tú lo haces manualmente.',
                  style: CessumType.label(11, color: cessumMuted(context))),
              secondary: _togglingAuto
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(Icons.schedule,
                      color: _autoActivo! ? cessumRed : cessumMuted(context)),
            ),
          ),
        ],
        if (_resultado != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cessumGold.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(_resultado!,
                style: CessumType.body(13, color: cessumInk(context))),
          ),
        ],
        const SizedBox(height: 16),
        Text('Recibirán recordatorio:',
            style: CessumType.label(12, color: cessumMuted(context))),
        const SizedBox(height: 6),
        for (final d in _docentes) _tarjetaDocente(d),
      ],
    );
  }

  Widget _tarjetaDocente(Map<String, dynamic> d) {
    final isDark = cessumIsDark(context);
    final nombre = (d['nombre'] ?? '').toString();
    final correo = (d['correo'] ?? '').toString();
    final materias = (d['materias'] as List<dynamic>? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF211F1D) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cessumRed.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(nombre,
              style: CessumType.heading(14, color: cessumInk(context))),
          if (correo.isNotEmpty)
            Text(correo,
                style: CessumType.label(11, color: cessumMuted(context))),
          const SizedBox(height: 8),
          for (final m in materias)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    (m['estado'] == 'sin_iniciar')
                        ? Icons.radio_button_unchecked
                        : Icons.timelapse,
                    size: 15,
                    color: cessumRed,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${m['materia']}  ·  G${m['grupo']}  ·  '
                      '${m['estado'] == 'sin_iniciar' ? 'Sin iniciar' : 'Parcial ${m['porcentaje']}%'}',
                      style: CessumType.body(12, color: cessumInk(context)),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

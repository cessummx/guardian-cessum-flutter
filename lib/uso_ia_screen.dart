import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

/// Panel de administrador: cuánto se usa el asistente de IA.
/// Muestra consultas (preguntas) de hoy, semana, mes y total, por rol,
/// los usuarios que más la usan y una gráfica de los últimos 14 días.
class UsoIaScreen extends StatefulWidget {
  const UsoIaScreen({super.key});

  @override
  State<UsoIaScreen> createState() => _UsoIaScreenState();
}

class _UsoIaScreenState extends State<UsoIaScreen> {
  bool _cargando = true;
  String? _error;

  int _total = 0, _hoy = 0, _semana = 0, _mes = 0, _usuariosUnicos = 0;
  Map<String, int> _porRol = {};
  List<Map<String, dynamic>> _top = [];
  List<Map<String, dynamic>> _serie = [];

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
      final correo = (await SessionStore.realEmail()) ?? '';
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'ia_uso',
        'actor': correo,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) {
        throw Exception(data['error'] ?? 'No se pudo cargar.');
      }
      int n(dynamic v) => v is int ? v : int.tryParse('$v') ?? 0;
      setState(() {
        _total = n(data['total']);
        _hoy = n(data['hoy']);
        _semana = n(data['semana']);
        _mes = n(data['mes']);
        _usuariosUnicos = n(data['usuariosUnicos']);
        _porRol = ((data['porRol'] as Map?) ?? {})
            .map((k, v) => MapEntry(k.toString(), n(v)));
        _top = ((data['topUsuarios'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _serie = ((data['serie'] as List?) ?? [])
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Uso de IA'),
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
              : _contenido(),
    );
  }

  Widget _vistaError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, color: cessumRed, size: 48),
            const SizedBox(height: 12),
            Text(_error ?? '', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: _cargar,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _contenido() {
    return RefreshIndicator(
      color: cessumRed,
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              _stat('Hoy', _hoy, cessumRed),
              const SizedBox(width: 10),
              _stat('Últimos 7 días', _semana, cessumGold),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _stat('Últimos 30 días', _mes, cessumRed),
              const SizedBox(width: 10),
              _stat('Total histórico', _total, const Color(0xFF555555)),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: _cajaDeco(),
            child: Row(
              children: [
                const Icon(Icons.people_alt_outlined, color: cessumGold),
                const SizedBox(width: 10),
                Text('$_usuariosUnicos',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: cessumInk(context))),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('usuarios distintos han usado la IA',
                      style: TextStyle(color: cessumMuted(context), fontSize: 13)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _titulo('Consultas por día (últimos 14)'),
          const SizedBox(height: 8),
          _grafica(),
          const SizedBox(height: 18),
          if (_porRol.isNotEmpty) ...[
            _titulo('Por tipo de usuario'),
            const SizedBox(height: 8),
            _porRolWidget(),
            const SizedBox(height: 18),
          ],
          _titulo('Quién la usa más'),
          const SizedBox(height: 8),
          _topWidget(),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cessumGold.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: cessumGold.withValues(alpha: 0.3)),
            ),
            child: Text(
              'Cada número es una consulta (pregunta) hecha al asistente de IA. '
              'El conteo exacto de tokens del proveedor no se registra por '
              'consulta; aquí se mide el volumen de uso.',
              style:
                  TextStyle(fontSize: 12, color: cessumMuted(context), height: 1.35),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _stat(String etq, int valor, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
        decoration: _cajaDeco(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$valor',
                style: TextStyle(
                    fontSize: 26, fontWeight: FontWeight.w800, color: color)),
            const SizedBox(height: 2),
            Text(etq,
                style: TextStyle(fontSize: 12.5, color: cessumMuted(context))),
          ],
        ),
      ),
    );
  }

  Widget _grafica() {
    if (_serie.isEmpty) {
      return Text('Sin datos todavía.',
          style: TextStyle(color: cessumMuted(context)));
    }
    int maxN = 1;
    for (final d in _serie) {
      final v = d['n'] is int ? d['n'] as int : int.tryParse('${d['n']}') ?? 0;
      if (v > maxN) maxN = v;
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 6),
      decoration: _cajaDeco(),
      child: SizedBox(
        height: 130,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: _serie.map((d) {
            final v =
                d['n'] is int ? d['n'] as int : int.tryParse('${d['n']}') ?? 0;
            final dia = (d['dia'] ?? '').toString();
            final etq = dia.length >= 10 ? dia.substring(8, 10) : dia;
            final alturaMax = 90.0;
            final h = maxN == 0 ? 0.0 : (v / maxN) * alturaMax;
            return Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(v > 0 ? '$v' : '',
                      style: TextStyle(
                          fontSize: 9, color: cessumFaint(context))),
                  const SizedBox(height: 2),
                  Container(
                    height: h < 3 && v > 0 ? 3 : h,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: v > 0 ? cessumRed : cessumMuted(context).withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(etq,
                      style: TextStyle(
                          fontSize: 9, color: cessumFaint(context))),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _porRolWidget() {
    final entradas = _porRol.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: entradas.map((e) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
          ),
          child: Text(
            '${_rolBonito(e.key)}: ${e.value}',
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: cessumRed),
          ),
        );
      }).toList(),
    );
  }

  Widget _topWidget() {
    if (_top.isEmpty) {
      return Text('Nadie ha usado la IA todavía.',
          style: TextStyle(color: cessumMuted(context)));
    }
    return Container(
      decoration: _cajaDeco(),
      child: Column(
        children: List.generate(_top.length, (i) {
          final u = _top[i];
          final nombre = (u['nombre'] ?? '').toString();
          final correo = (u['correo'] ?? '').toString();
          final rol = (u['rol'] ?? '').toString();
          final nn = u['n'] is int ? u['n'] as int : int.tryParse('${u['n']}') ?? 0;
          return Column(
            children: [
              if (i > 0) const Divider(height: 1),
              ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: 14,
                  backgroundColor: cessumRed.withValues(alpha: 0.12),
                  child: Text('${i + 1}',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: cessumRed)),
                ),
                title: Text(nombre.isEmpty ? correo : nombre,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13.5)),
                subtitle: Text(
                  [
                    if (_rolBonito(rol).isNotEmpty) _rolBonito(rol),
                    if (correo.isNotEmpty) correo,
                  ].join(' · '),
                  style: const TextStyle(fontSize: 11.5),
                ),
                trailing: Text('$nn',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: cessumRed,
                        fontSize: 16)),
              ),
            ],
          );
        }),
      ),
    );
  }

  String _rolBonito(String r) {
    switch (r.toLowerCase()) {
      case 'total':
        return 'Administrador';
      case 'admin':
        return 'Administrador';
      case 'docente':
        return 'Docente';
      case 'alumno':
        return 'Alumno';
      default:
        return r.isEmpty ? '' : r;
    }
  }

  Widget _titulo(String t) {
    return Text(t,
        style: const TextStyle(
            fontSize: 15, fontWeight: FontWeight.w800, color: cessumRed));
  }

  BoxDecoration _cajaDeco() {
    return BoxDecoration(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
    );
  }
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

/// Indicador discreto: muestra si el Guardián responde y la versión publicada
/// (de version.json). Tócalo para volver a verificar.
class EstadoConexion extends StatefulWidget {
  const EstadoConexion({super.key});

  @override
  State<EstadoConexion> createState() => _EstadoConexionState();
}

class _EstadoConexionState extends State<EstadoConexion> {
  bool _verificando = true;
  bool _enLinea = false;
  String _version = '';

  @override
  void initState() {
    super.initState();
    _verificar();
  }

  Future<void> _verificar() async {
    setState(() => _verificando = true);
    bool linea = false;
    String ver = '';
    try {
      final uri = Uri.parse(guardianUrl)
          .replace(queryParameters: {'accion': 'ping'});
      final resp = await http.get(uri).timeout(const Duration(seconds: 10));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      linea = data['ok'] == true;
    } catch (_) {
      linea = false;
    }
    try {
      final vresp = await http
          .get(Uri.base.resolve('version.json'))
          .timeout(const Duration(seconds: 10));
      final vd = jsonDecode(vresp.body);
      if (vd is Map) {
        ver = (vd['version'] ?? vd['build'] ?? vd['v'] ?? '').toString();
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _enLinea = linea;
      _version = ver;
      _verificando = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final color = _verificando
        ? Colors.grey
        : (_enLinea ? const Color(0xFF1E8E3E) : cessumRed);
    final txt = _verificando
        ? 'Verificando conexión...'
        : (_enLinea ? 'Guardián en línea' : 'Sin conexión con el Guardián');
    return InkWell(
      onTap: _verificando ? null : _verificar,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 7),
            Text(txt,
                style: const TextStyle(fontSize: 11.5, color: Colors.black54)),
            if (_version.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text('· v$_version',
                  style:
                      const TextStyle(fontSize: 11.5, color: Colors.black38)),
            ],
            const SizedBox(width: 6),
            const Icon(Icons.refresh, size: 13, color: Colors.black26),
          ],
        ),
      ),
    );
  }
}

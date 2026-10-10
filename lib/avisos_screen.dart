import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'student_profile.dart';

/// Trae los avisos vigentes que aplican al perfil del alumno.
class AvisosService {
  static Future<List<Map<String, dynamic>>> para(StudentProfile p) async {
    final uri = Uri.parse('$guardianUrl?accion=avisos_para'
        '&programa=${Uri.encodeComponent(p.programa)}'
        '&modalidad=${Uri.encodeComponent(p.modalidad)}'
        '&generacion=${Uri.encodeComponent(p.generacion)}'
        '&grupo=');
    final resp = await http.get(uri).timeout(const Duration(seconds: 30));
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    if (data['ok'] != true) return [];
    return (data['avisos'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }
}

/// Lista completa de avisos vigentes para el alumno.
class AvisosScreen extends StatelessWidget {
  final List<Map<String, dynamic>> avisos;
  const AvisosScreen({super.key, required this.avisos});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Avisos',
            style: TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: avisos.isEmpty
          ? Center(
              child: Text('No hay avisos por el momento.',
                  style: TextStyle(color: cessumMuted(context))),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: avisos.length,
              itemBuilder: (ctx, i) {
                final a = avisos[i];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.campaign,
                                color: cessumRed, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                (a['titulo'] ?? '') as String,
                                style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          (a['fecha'] ?? '') as String,
                          style: TextStyle(
                              fontSize: 11, color: cessumFaint(ctx)),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          (a['mensaje'] ?? '') as String,
                          style: const TextStyle(fontSize: 14, height: 1.5),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

/// Banner para el inicio: muestra el aviso más reciente y abre la lista.
class AvisosBanner extends StatelessWidget {
  final List<Map<String, dynamic>> avisos;
  const AvisosBanner({super.key, required this.avisos});

  @override
  Widget build(BuildContext context) {
    if (avisos.isEmpty) return const SizedBox.shrink();
    final a = avisos.first;
    return Material(
      color: cessumGold.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => AvisosScreen(avisos: avisos)),
        ),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cessumGold.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              const Icon(Icons.campaign, color: cessumGold, size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (a['titulo'] ?? '') as String,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: cessumInk(context)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      avisos.length == 1
                          ? (a['mensaje'] ?? '') as String
                          : '${(a['mensaje'] ?? '') as String}  ·  ${avisos.length} avisos',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: cessumGold),
            ],
          ),
        ),
      ),
    );
  }
}

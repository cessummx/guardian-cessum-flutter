import 'package:flutter/material.dart';

import 'constants.dart';
import 'cessum_ui.dart';
import 'student_profile.dart';
import 'maaso_juego_screen.dart';
import 'memorama_screen.dart';
import 'atrapa_maaso_screen.dart';
import 'camino_maaso_screen.dart';
import 'ranking_juegos_screen.dart';

/// Hub de Juegos: el alumno entra a "Juegos", elige cuál jugar y puede ver el
/// ranking (Top 10) de toda la comunidad.
/// (2-oct-2026) Los cuatro juegos se rehicieron con control de teclado para
/// computadora, pausa, niveles y mecánicas nuevas; aquí se actualizaron las
/// descripciones y se avisa que en PC se juega con el teclado.
class JuegosHubScreen extends StatelessWidget {
  final StudentProfile perfil;
  const JuegosHubScreen({super.key, required this.perfil});

  @override
  Widget build(BuildContext context) {
    final juegos = <_Juego>[
      _Juego(
        emoji: '🦌',
        titulo: 'MAASO Salta',
        detalle: 'Corre, salta y agáchate. Power-ups, rachas y ciclo de día y noche.',
        teclas: 'Espacio salta · ↓ agacha · Esc pausa',
        destino: MaasoJuegoScreen(perfil: perfil),
      ),
      _Juego(
        emoji: '🃏',
        titulo: 'Memorama del Mayo',
        detalle: 'Tres dificultades, rachas que multiplican, contrarreloj y pistas.',
        teclas: 'Flechas mueven · Enter voltea · H pista',
        destino: MemoramaScreen(perfil: perfil),
      ),
      _Juego(
        emoji: '🎯',
        titulo: 'Atrapa al MAASO',
        detalle: 'Venado dorado, cactus que roban tiempo, niveles y doble aparición.',
        teclas: 'Q W E / A S D / Z X C · Esc pausa',
        destino: AtrapaMaasoScreen(perfil: perfil),
      ),
      _Juego(
        emoji: '🐍',
        titulo: 'El Camino del MAASO',
        detalle: 'La culebrita de CESSUM: libros, birretes, estrellas ×2 y cactus. Modo infinito.',
        teclas: 'Flechas o WASD · Espacio pausa',
        destino: CaminoMaasoScreen(perfil: perfil),
      ),
    ];

    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Juegos'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Juega, compite y aparece en el Top 10 de CESSUM.',
            style: TextStyle(color: cessumMuted(context)),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: cessumGold.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: cessumGold.withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                const Text('💻', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'En computadora, todos los juegos se controlan con el teclado. '
                    'Cada uno te muestra sus teclas antes de empezar.',
                    style: TextStyle(fontSize: 12.5, color: cessumMuted(context)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Acceso destacado al ranking.
          Card(
            color: cessumRed,
            margin: const EdgeInsets.only(bottom: 16),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              leading: const Text('🏆', style: TextStyle(fontSize: 28)),
              title: const Text(
                'Ranking · Top 10',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w800),
              ),
              subtitle: const Text(
                'Mira quién va ganando en cada juego',
                style: TextStyle(color: Colors.white70),
              ),
              trailing: const Icon(Icons.chevron_right, color: Colors.white),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => RankingJuegosScreen(perfil: perfil),
                ),
              ),
            ),
          ),
          ...juegos.map((j) {
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                leading: Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: cessumGold.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(j.emoji, style: const TextStyle(fontSize: 26)),
                ),
                title: Text(j.titulo,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(j.detalle),
                    const SizedBox(height: 4),
                    Text('⌨️ ${j.teclas}',
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: cessumMuted(context))),
                  ],
                ),
                isThreeLine: true,
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => j.destino),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _Juego {
  final String emoji;
  final String titulo;
  final String detalle;
  final String teclas;
  final Widget destino;
  _Juego({
    required this.emoji,
    required this.titulo,
    required this.detalle,
    required this.teclas,
    required this.destino,
  });
}

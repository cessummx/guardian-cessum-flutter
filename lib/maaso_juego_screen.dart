import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'constants.dart';
import 'student_profile.dart';
import 'ranking_api.dart';

/// Mini-juego "MAASO Salta" (2-oct-2026, versión ampliada).
///
/// El venado de CESSUM corre por el Mayo y esquiva obstáculos. Qué cambió
/// respecto a la primera versión (que solo saltaba al tocar la pantalla):
///
///  · TECLADO (PC): Espacio / ↑ / W saltan; ↓ / S agachan (y en el aire,
///    caída rápida); Esc / P pausan; Enter o Espacio arrancan desde los
///    paneles. En móvil: toca para saltar, mantén el botón 🔽 para agacharte.
///  · SALTO VARIABLE: mantener la tecla salta más alto, soltarla pronto corta
///    el salto. Y si pulsas salto justo antes de aterrizar, salta al tocar el
///    suelo (jump buffer): se siente preciso en vez de "sordo".
///  · AGACHARSE: aparecen aves 🦅 a media altura; se esquivan agachándose o
///    con un salto alto. Agacharse en el aire te baja de golpe.
///  · OBSTÁCULOS variados (cactus sencillo y doble, libros, roca, ave),
///    LIBROS 📖 coleccionables en arcos (+5) y POWER-UPS: 🎓 escudo (perdona
///    un choque), 🌟 puntos dobles, ⏳ cámara lenta.
///  · RACHA y "¡Perfecto!" por esquivar al ras; textos flotantes de puntos.
///  · CICLO DÍA/NOCHE con parallax (dunas, cactus lejanos, nubes, estrellas).
///  · Ticker con tiempo real (suave en web, no se descompone si la pestaña
///    pierde foco), pausa, sacudida al chocar, récord de sesión.
///
/// Sigue autocontenido: sin backend, sin assets, solo emojis y colores de
/// CESSUM. El puntaje se manda al ranking con la MISMA clave de siempre.
int _maasoBest = 0;

enum _Fase { lista, jugando, pausa, fin }

enum _TipoObs { cactus, cactusDoble, libros, roca, ave }

enum _TipoPower { escudo, doble, lento }

class MaasoJuegoScreen extends StatefulWidget {
  final StudentProfile perfil;
  const MaasoJuegoScreen({super.key, required this.perfil});

  @override
  State<MaasoJuegoScreen> createState() => _MaasoJuegoScreenState();
}

class _MaasoJuegoScreenState extends State<MaasoJuegoScreen>
    with SingleTickerProviderStateMixin {
  // ── Medidas y física (píxeles; el venado va fijo a la izquierda) ──
  static const double _deerX = 48;
  static const double _deerSize = 38;
  static const double _groundH = 56;
  static const double _gravity = 2700;
  static const double _jumpV = 760;
  static const double _fastFallV = -1100;
  static const double _bufferSaltoMax = 0.12; // s de tolerancia del jump buffer

  final Random _rng = Random();
  final FocusNode _foco = FocusNode();
  late final Ticker _ticker;
  Duration _ultimo = Duration.zero;

  _Fase _fase = _Fase.lista;
  double _w = 320;
  double _hArea = 400;

  // Venado
  double _deerY = 0;
  double _vel = 0;
  bool _enSuelo = true;
  bool _agachado = false;
  bool _saltoCortado = false;
  bool _saltoPresionado = false;
  double _bufferSalto = 0;

  // Mundo
  double _dist = 0;
  double _puntosDist = 0;
  int _bonus = 0;
  double _speed = 220;
  double _spawnObs = 1.2;
  double _spawnExtra = 2.5;
  int _score = 0;
  int _racha = 0;
  int _mejorRacha = 0;
  int _esquivados = 0;
  int _librosTomados = 0;
  final List<_Obs> _obs = [];
  final List<_Item> _items = [];
  final List<_Flotante> _flotantes = [];

  // Power-ups activos
  bool _escudo = false;
  double _dobleRestante = 0;
  double _lentoRestante = 0;

  // Efectos
  double _shake = 0;
  double _flashEscudo = 0;
  bool _nuevoRecord = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _foco.dispose();
    super.dispose();
  }

  // ── Control de partida ──
  void _start() {
    setState(() {
      _fase = _Fase.jugando;
      _deerY = 0;
      _vel = 0;
      _enSuelo = true;
      _agachado = false;
      _saltoCortado = false;
      _saltoPresionado = false;
      _bufferSalto = 0;
      _dist = 0;
      _puntosDist = 0;
      _bonus = 0;
      _speed = 220;
      _spawnObs = 1.2;
      _spawnExtra = 2.5;
      _score = 0;
      _racha = 0;
      _mejorRacha = 0;
      _esquivados = 0;
      _librosTomados = 0;
      _obs.clear();
      _items.clear();
      _flotantes.clear();
      _escudo = false;
      _dobleRestante = 0;
      _lentoRestante = 0;
      _shake = 0;
      _flashEscudo = 0;
      _nuevoRecord = false;
    });
    _ultimo = Duration.zero;
    if (!_ticker.isActive) _ticker.start();
    _foco.requestFocus();
  }

  void _pausar() {
    if (_fase != _Fase.jugando) return;
    setState(() => _fase = _Fase.pausa);
    if (_ticker.isActive) _ticker.stop();
  }

  void _reanudar() {
    if (_fase != _Fase.pausa) return;
    _ultimo = Duration.zero;
    setState(() => _fase = _Fase.jugando);
    if (!_ticker.isActive) _ticker.start();
    _foco.requestFocus();
  }

  void _fin() {
    _nuevoRecord = _score > _maasoBest && _maasoBest > 0;
    if (_score > _maasoBest) _maasoBest = _score;
    RankingApi.enviar(
      matricula: widget.perfil.matricula,
      nombre: widget.perfil.nombreCompleto,
      juego: 'MAASO Salta',
      puntaje: _score,
    );
    if (!mounted) return;
    setState(() {
      _fase = _Fase.fin;
      _shake = 0.45;
    });
  }

  // ── Entrada unificada (teclado y táctil) ──
  void _pressJump() {
    if (_fase == _Fase.lista || _fase == _Fase.fin) {
      _start();
      return;
    }
    if (_fase == _Fase.pausa) {
      _reanudar();
      return;
    }
    _saltoPresionado = true;
    if (_enSuelo) {
      _saltar();
    } else {
      _bufferSalto = _bufferSaltoMax;
    }
  }

  void _releaseJump() {
    _saltoPresionado = false;
    // Soltar mientras sube = salto corto.
    if (!_enSuelo && _vel > 0 && !_saltoCortado) {
      _vel *= 0.45;
      _saltoCortado = true;
    }
  }

  void _saltar() {
    _vel = _jumpV;
    _enSuelo = false;
    _saltoCortado = false;
    _agachado = false;
    _bufferSalto = 0;
  }

  void _pressDuck() {
    if (_fase != _Fase.jugando) return;
    _agachado = true;
    if (!_enSuelo && _vel > _fastFallV) _vel = _fastFallV; // caída rápida
  }

  void _releaseDuck() {
    _agachado = false;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    final k = e.logicalKey;
    final esSalto = k == LogicalKeyboardKey.space ||
        k == LogicalKeyboardKey.arrowUp ||
        k == LogicalKeyboardKey.keyW;
    final esAgachar =
        k == LogicalKeyboardKey.arrowDown || k == LogicalKeyboardKey.keyS;
    final esPausa =
        k == LogicalKeyboardKey.escape || k == LogicalKeyboardKey.keyP;
    final esEnter = k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.numpadEnter;

    if (e is KeyDownEvent) {
      if (esSalto || (esEnter && _fase != _Fase.jugando)) {
        _pressJump();
        return KeyEventResult.handled;
      }
      if (esAgachar) {
        _pressDuck();
        return KeyEventResult.handled;
      }
      if (esPausa) {
        if (_fase == _Fase.jugando) {
          _pausar();
        } else if (_fase == _Fase.pausa) {
          _reanudar();
        }
        return KeyEventResult.handled;
      }
    } else if (e is KeyUpEvent) {
      if (esSalto) {
        _releaseJump();
        return KeyEventResult.handled;
      }
      if (esAgachar) {
        _releaseDuck();
        return KeyEventResult.handled;
      }
    } else if (e is KeyRepeatEvent) {
      // Mantener presionada la tecla no debe disparar nada nuevo.
      if (esSalto || esAgachar) return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ── Bucle principal ──
  void _onTick(Duration elapsed) {
    if (_fase != _Fase.jugando) {
      // Tras chocar, solo decae la sacudida y luego se detiene el ticker.
      if (_shake > 0) {
        _shake = max(0, _shake - 0.016);
        if (mounted) setState(() {});
      } else if (_ticker.isActive) {
        _ticker.stop();
      }
      return;
    }
    if (_ultimo == Duration.zero) {
      _ultimo = elapsed;
      return;
    }
    double dt = (elapsed - _ultimo).inMicroseconds / 1e6;
    _ultimo = elapsed;
    if (dt > 0.05) dt = 0.05; // tras perder el foco, no saltes en el tiempo
    if (dt <= 0) return;

    final factor = _lentoRestante > 0 ? 0.62 : 1.0;
    final speedEf = _speed * factor;
    final dobleActivo = _dobleRestante > 0;

    // Física del venado.
    _vel -= _gravity * dt;
    _deerY += _vel * dt;
    if (_deerY <= 0) {
      _deerY = 0;
      _vel = 0;
      if (!_enSuelo) {
        _enSuelo = true;
        if (_bufferSalto > 0 || _saltoPresionado) _saltar();
      }
    }
    if (_bufferSalto > 0) _bufferSalto -= dt;

    // Avance, puntos por distancia y velocidad.
    _dist += speedEf * dt;
    _puntosDist += speedEf * dt / 40 * (dobleActivo ? 2 : 1);
    _speed = 220 + min(_dist / 60, 300.0);
    if (_dobleRestante > 0) _dobleRestante -= dt;
    if (_lentoRestante > 0) _lentoRestante -= dt;
    if (_flashEscudo > 0) _flashEscudo -= dt;

    // Mover obstáculos, items y textos.
    for (final o in _obs) {
      o.x -= speedEf * dt;
    }
    for (final it in _items) {
      it.x -= speedEf * dt;
      it.bob += dt * 4;
    }
    for (final f in _flotantes) {
      f.y += 38 * dt;
      f.vida -= dt;
    }
    _flotantes.removeWhere((f) => f.vida <= 0);
    _items.removeWhere((it) => it.x < -40);

    final hitDeer = _hitboxVenado();

    // Esquivados: obstáculos que ya pasaron al venado.
    for (final o in _obs) {
      if (!o.pasado && o.x + o.w < _deerX) {
        o.pasado = true;
        _esquivados++;
        _racha++;
        if (_racha > _mejorRacha) _mejorRacha = _racha;
        // ¿Perfecto? Pasó un obstáculo terrestre con el venado apenas en el aire.
        if (o.tipo != _TipoObs.ave && !_enSuelo && _deerY < 26 && _deerY > 2) {
          final pts = dobleActivo ? 20 : 10;
          _bonus += pts;
          _flotar('¡Perfecto! +$pts', _deerX + 10, _groundH + _deerY + 50,
              const Color(0xFF1E8E3E));
        }
        if (_racha % 5 == 0) {
          final pts = dobleActivo ? 50 : 25;
          _bonus += pts;
          _flotar('🔥 Racha $_racha +$pts', _deerX + 10,
              _groundH + _deerY + 70, cessumGold);
        }
      }
    }
    _obs.removeWhere((o) => o.x < -120);

    // Generar obstáculos.
    _spawnObs -= dt;
    if (_spawnObs <= 0) {
      _generarObstaculo();
      // Espaciado proporcional a la velocidad, con mínimo jugable.
      final base = (_rng.nextDouble() * 160 + 260) / _speed;
      _spawnObs = max(0.55, base);
    }

    // Generar items (libros en arco o power-up).
    _spawnExtra -= dt;
    if (_spawnExtra <= 0) {
      _generarItems();
      _spawnExtra = _rng.nextDouble() * 3.0 + 2.2;
    }

    // Recoger items.
    _items.removeWhere((it) {
      final r = Rect.fromLTWH(it.x + 4, _groundH + it.y + 4, 22, 22);
      if (!r.overlaps(hitDeer)) return false;
      _recoger(it, dobleActivo);
      return true;
    });

    // Colisión con obstáculos.
    bool hit = false;
    for (final o in _obs) {
      if (o.pasado) continue;
      final r = Rect.fromLTWH(o.x + 5, _groundH + o.base + 3, o.w - 10, o.h - 6);
      if (r.overlaps(hitDeer)) {
        if (_escudo) {
          // El escudo absorbe el golpe y el obstáculo desaparece.
          _escudo = false;
          _flashEscudo = 0.4;
          o.pasado = true;
          o.x = -999;
          _flotar('🎓 ¡Escudo!', _deerX, _groundH + _deerY + 60, cessumRed);
        } else {
          hit = true;
        }
        break;
      }
    }

    _score = _puntosDist.floor() + _bonus;

    if (!mounted) return;
    if (hit) {
      _fin();
      return;
    }
    setState(() {});
  }

  Rect _hitboxVenado() {
    final alto = _agachado ? 15.0 : 28.0;
    return Rect.fromLTWH(_deerX + 7, _groundH + _deerY + 3, 24, alto);
  }

  void _flotar(String texto, double x, double y, Color color) {
    _flotantes.add(_Flotante(texto: texto, x: x, y: y, color: color));
  }

  void _generarObstaculo() {
    // Las aves aparecen a partir de cierta distancia para que el jugador
    // aprenda primero a saltar.
    final permiteAve = _dist > 900;
    final roll = _rng.nextDouble();
    _TipoObs t;
    if (permiteAve && roll < 0.22) {
      t = _TipoObs.ave;
    } else if (roll < 0.42) {
      t = _TipoObs.cactus;
    } else if (roll < 0.58 && _dist > 1500) {
      t = _TipoObs.cactusDoble;
    } else if (roll < 0.80) {
      t = _TipoObs.libros;
    } else {
      t = _TipoObs.roca;
    }
    switch (t) {
      case _TipoObs.cactus:
        _obs.add(_Obs(t, _w + 10, '🌵', 28, 42, 0));
        break;
      case _TipoObs.cactusDoble:
        _obs.add(_Obs(t, _w + 10, '🌵🌵', 64, 42, 0));
        break;
      case _TipoObs.libros:
        _obs.add(_Obs(t, _w + 10, '📚', 32, 30, 0));
        break;
      case _TipoObs.roca:
        _obs.add(_Obs(t, _w + 10, '🪨', 34, 28, 0));
        break;
      case _TipoObs.ave:
        // Vuela a la altura del torso: de pie choca, agachado pasa.
        _obs.add(_Obs(t, _w + 10, '🦅', 34, 26, 24));
        break;
    }
  }

  void _generarItems() {
    final roll = _rng.nextDouble();
    if (roll < 0.30 && _dist > 600) {
      // Power-up flotando a media altura.
      final tipos = _TipoPower.values;
      final tp = tipos[_rng.nextInt(tipos.length)];
      final emoji = tp == _TipoPower.escudo
          ? '🎓'
          : tp == _TipoPower.doble
              ? '🌟'
              : '⏳';
      _items.add(_Item(
          tipo: tp, x: _w + 40, y: 55 + _rng.nextDouble() * 25, emoji: emoji));
    } else {
      // Arco de 3 libros a alturas crecientes o decrecientes.
      final alto = _rng.nextBool();
      for (int i = 0; i < 3; i++) {
        final y = alto ? 48.0 + i * 14 : 70.0 - i * 10;
        _items.add(_Item(tipo: null, x: _w + 40 + i * 34, y: y, emoji: '📖'));
      }
    }
  }

  void _recoger(_Item it, bool dobleActivo) {
    final tp = it.tipo;
    if (tp == null) {
      final pts = dobleActivo ? 10 : 5;
      _bonus += pts;
      _librosTomados++;
      _flotar('+$pts', it.x, _groundH + it.y + 20, cessumRed);
      return;
    }
    switch (tp) {
      case _TipoPower.escudo:
        _escudo = true;
        _flotar('🎓 Escudo', it.x, _groundH + it.y + 20, cessumRed);
        break;
      case _TipoPower.doble:
        _dobleRestante = 8;
        _flotar('🌟 Puntos ×2', it.x, _groundH + it.y + 20, cessumGold);
        break;
      case _TipoPower.lento:
        _lentoRestante = 6;
        _flotar('⏳ Cámara lenta', it.x, _groundH + it.y + 20,
            const Color(0xFF1565C0));
        break;
    }
  }

  // ── Cielo según el ciclo día/noche ──
  // 0 = mediodía, 0.25 = atardecer, 0.5 = noche, 0.75 = amanecer.
  double get _horaDia => (_dist / 7000) % 1.0;

  bool get _esNoche => _horaDia > 0.33 && _horaDia < 0.7;

  List<Color> _coloresCielo() {
    const dia = [Color(0xFFF5F1E8), Color(0xFFEAD9B0)];
    const tarde = [Color(0xFFF2B27A), Color(0xFFE6714A)];
    const noche = [Color(0xFF1B1F3B), Color(0xFF3A2E5C)];
    const alba = [Color(0xFFB7C4E0), Color(0xFFF2C9A0)];
    final h = _horaDia;
    List<Color> a;
    List<Color> b;
    double t;
    if (h < 0.25) {
      a = dia;
      b = tarde;
      t = h / 0.25;
    } else if (h < 0.5) {
      a = tarde;
      b = noche;
      t = (h - 0.25) / 0.25;
    } else if (h < 0.75) {
      a = noche;
      b = alba;
      t = (h - 0.5) / 0.25;
    } else {
      a = alba;
      b = dia;
      t = (h - 0.75) / 0.25;
    }
    return [
      Color.lerp(a[0], b[0], t) ?? a[0],
      Color.lerp(a[1], b[1], t) ?? a[1],
    ];
  }

  // ── UI ──
  @override
  Widget build(BuildContext context) {
    final cielo = _coloresCielo();
    final noche = _esNoche;
    final textoCielo = noche ? Colors.white : Colors.black87;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('MAASO Salta',
            style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          if (_fase == _Fase.jugando || _fase == _Fase.pausa)
            IconButton(
              tooltip: _fase == _Fase.pausa ? 'Reanudar (Esc)' : 'Pausa (Esc)',
              icon: Icon(_fase == _Fase.pausa ? Icons.play_arrow : Icons.pause),
              onPressed: _fase == _Fase.pausa ? _reanudar : _pausar,
            ),
        ],
      ),
      body: Focus(
        focusNode: _foco,
        autofocus: true,
        onKeyEvent: _onKey,
        child: LayoutBuilder(
          builder: (ctx, cons) {
            _w = cons.maxWidth;
            _hArea = cons.maxHeight;
            final dx = _shake > 0 ? (_rng.nextDouble() - 0.5) * 14 * _shake : 0.0;
            final dy = _shake > 0 ? (_rng.nextDouble() - 0.5) * 10 * _shake : 0.0;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (_) {
                _foco.requestFocus();
                _pressJump();
              },
              onTapUp: (_) => _releaseJump(),
              onTapCancel: _releaseJump,
              child: Transform.translate(
                offset: Offset(dx, dy),
                child: Stack(
                  children: [
                    // Cielo
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: cielo,
                          ),
                        ),
                      ),
                    ),
                    // Estrellas (de noche)
                    if (noche) ..._estrellas(),
                    // Sol / luna
                    Positioned(
                      top: 18,
                      right: 24,
                      child: Text(noche ? '🌙' : '☀️',
                          style: const TextStyle(fontSize: 34)),
                    ),
                    // Nubes (parallax muy lento)
                    ..._nubes(noche),
                    // Dunas lejanas
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: _groundH,
                      height: 110,
                      child: CustomPaint(
                        painter: _DunasPainter(
                            offset: _dist * 0.18,
                            color: noche
                                ? const Color(0xFF2E3A5C)
                                : const Color(0xFFD9BE86)),
                      ),
                    ),
                    // Cactus de fondo (parallax medio)
                    ..._cactusFondo(),
                    // Piso
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: _groundH,
                      child: CustomPaint(
                        painter: _PisoPainter(
                          offset: _dist,
                          color: noche
                              ? const Color(0xFF4A3A22)
                              : const Color(0xFF7A5A2E),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: _groundH - 6,
                      height: 6,
                      child: Container(color: cessumGold),
                    ),
                    // Items
                    ..._items.map((it) => Positioned(
                          left: it.x,
                          bottom: _groundH + it.y + sin(it.bob) * 3,
                          child: Text(it.emoji,
                              style: TextStyle(
                                  fontSize: it.tipo == null ? 22 : 28,
                                  height: 1)),
                        )),
                    // Obstáculos
                    ..._obs.map((o) => Positioned(
                          left: o.x,
                          bottom: _groundH + o.base,
                          child: Text(o.emoji,
                              style: TextStyle(fontSize: o.h, height: 1)),
                        )),
                    // Venado
                    Positioned(
                      left: _deerX,
                      bottom: _groundH + _deerY,
                      child: _venado(),
                    ),
                    // Textos flotantes
                    ..._flotantes.map((f) => Positioned(
                          left: f.x,
                          bottom: f.y,
                          child: Opacity(
                            opacity: (f.vida / 0.9).clamp(0.0, 1.0).toDouble(),
                            child: Text(f.texto,
                                style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                    color: f.color,
                                    shadows: const [
                                      Shadow(color: Colors.white, blurRadius: 4)
                                    ])),
                          ),
                        )),
                    // HUD
                    Positioned(top: 10, left: 14, child: _hud(textoCielo)),
                    // Botón agacharse (móvil)
                    if (_fase == _Fase.jugando)
                      Positioned(
                        right: 14,
                        bottom: _groundH + 10,
                        child: GestureDetector(
                          onTapDown: (_) => _pressDuck(),
                          onTapUp: (_) => _releaseDuck(),
                          onTapCancel: _releaseDuck,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.75),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: cessumGold, width: 2),
                            ),
                            child: const Text('🔽 Agáchate',
                                style: TextStyle(
                                    fontWeight: FontWeight.w800, fontSize: 13)),
                          ),
                        ),
                      ),
                    if (_fase != _Fase.jugando) _panel(),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _venado() {
    final inclinacion = (-_vel / 5000).clamp(-0.35, 0.35).toDouble();
    final bob = _enSuelo ? sin(_dist * 0.06) * 1.5 : 0.0;
    final Color anillo = _flashEscudo > 0
        ? cessumRed.withValues(alpha: (_flashEscudo * 2).clamp(0.0, 0.9).toDouble())
        : cessumGold.withValues(alpha: 0.8);
    return Transform.translate(
      offset: Offset(0, -bob),
      child: Transform.rotate(
        angle: inclinacion,
        alignment: Alignment.bottomCenter,
        child: Transform.scale(
          scaleY: _agachado ? 0.55 : 1.0,
          alignment: Alignment.bottomCenter,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (_escudo || _flashEscudo > 0)
                Container(
                  width: _deerSize + 14,
                  height: _deerSize + 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: anillo, width: 3),
                  ),
                ),
              const Text('🦌', style: TextStyle(fontSize: _deerSize, height: 1)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hud(Color texto) {
    final chips = <Widget>[];
    if (_escudo) chips.add(_chip('🎓 Escudo', cessumRed));
    if (_dobleRestante > 0) {
      chips.add(_chip('🌟 ×2 ${_dobleRestante.ceil()}s', cessumGold));
    }
    if (_lentoRestante > 0) {
      chips.add(_chip('⏳ ${_lentoRestante.ceil()}s', const Color(0xFF1565C0)));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('⭐ $_score     🏆 $_maasoBest',
            style: TextStyle(
                fontWeight: FontWeight.w800, fontSize: 16, color: texto)),
        if (_racha >= 3)
          Text('🔥 Racha $_racha',
              style: TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 12, color: texto)),
        if (chips.isNotEmpty) ...[
          const SizedBox(height: 4),
          Wrap(spacing: 6, children: chips),
        ],
      ],
    );
  }

  Widget _chip(String t, Color c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c, width: 1.5),
      ),
      child: Text(t,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: c)),
    );
  }

  List<Widget> _estrellas() {
    // Posiciones fijas pseudoaleatorias: no parpadean ni se mueven.
    final out = <Widget>[];
    for (int i = 0; i < 14; i++) {
      final x = ((i * 73) % 97) / 97 * _w;
      final y = 10 + ((i * 37) % 61) / 61 * (_hArea * 0.45);
      final tam = i % 3 == 0 ? 3.0 : 2.0;
      out.add(Positioned(
        left: x,
        top: y,
        child: Container(
          width: tam,
          height: tam,
          decoration:
              const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
        ),
      ));
    }
    return out;
  }

  List<Widget> _nubes(bool noche) {
    final out = <Widget>[];
    final ancho = _w + 160;
    for (int i = 0; i < 3; i++) {
      final base = i * (ancho / 3);
      var x = (base - _dist * 0.08) % ancho;
      if (x < 0) x += ancho;
      out.add(Positioned(
        top: 40 + i * 22.0,
        left: x - 80,
        child: Opacity(
          opacity: noche ? 0.35 : 0.9,
          child: Text('☁️', style: TextStyle(fontSize: 22 + i * 4.0)),
        ),
      ));
    }
    return out;
  }

  List<Widget> _cactusFondo() {
    final out = <Widget>[];
    final ancho = _w + 120;
    for (int i = 0; i < 4; i++) {
      final base = i * (ancho / 4) + 30;
      var x = (base - _dist * 0.45) % ancho;
      if (x < 0) x += ancho;
      out.add(Positioned(
        bottom: _groundH + 2,
        left: x - 60,
        child: Opacity(
          opacity: 0.35,
          child: Text('🌵', style: TextStyle(fontSize: 18 + (i % 2) * 6.0)),
        ),
      ));
    }
    return out;
  }

  Widget _panel() {
    final fin = _fase == _Fase.fin;
    final pausa = _fase == _Fase.pausa;
    final titulo = pausa
        ? 'Pausa'
        : fin
            ? (_nuevoRecord ? '🏆 ¡Nuevo récord!' : '¡Uy! Chocaste')
            : 'MAASO Salta';
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(20),
        constraints: const BoxConstraints(maxWidth: 380),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(color: Colors.black26, blurRadius: 16, offset: Offset(0, 6))
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🦌', style: TextStyle(fontSize: 40)),
            const SizedBox(height: 6),
            Text(titulo,
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w800, color: cessumRed)),
            const SizedBox(height: 10),
            if (fin) ...[
              _filaStat('Puntos', '$_score'),
              _filaStat('Mejor', '$_maasoBest'),
              _filaStat('Obstáculos esquivados', '$_esquivados'),
              _filaStat('Mejor racha', '$_mejorRacha'),
              _filaStat('Libros recogidos', '$_librosTomados'),
            ] else if (pausa) ...[
              const Text('Esc o Espacio para seguir.',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 14)),
            ] else ...[
              const Text(
                'Esquiva cactus, rocas y libros. Recoge 📖 y power-ups:\n'
                '🎓 escudo · 🌟 puntos ×2 · ⏳ cámara lenta.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13.5, height: 1.4),
              ),
              const SizedBox(height: 10),
              _teclas(),
              const SizedBox(height: 6),
              const Text('En móvil: toca para saltar, mantén 🔽 para agacharte.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: Colors.black54)),
            ],
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              ),
              onPressed: pausa ? _reanudar : _start,
              icon: Icon(pausa
                  ? Icons.play_arrow
                  : fin
                      ? Icons.refresh
                      : Icons.play_arrow),
              label: Text(pausa
                  ? 'Seguir'
                  : fin
                      ? 'Jugar de nuevo'
                      : 'Jugar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filaStat(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(k, style: const TextStyle(fontSize: 13.5, color: Colors.black54)),
          Text(v,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _teclas() {
    Widget tecla(String t) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xFFF3EEE3),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.black26),
          ),
          child: Text(t,
              style:
                  const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
        );
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        tecla('Espacio'),
        tecla('↑'),
        const Text('saltar (mantén = más alto)', style: TextStyle(fontSize: 11.5)),
        tecla('↓'),
        const Text('agacharte', style: TextStyle(fontSize: 11.5)),
        tecla('Esc'),
        const Text('pausa', style: TextStyle(fontSize: 11.5)),
      ],
    );
  }
}

// ── Modelos ──
class _Obs {
  final _TipoObs tipo;
  double x;
  final String emoji;
  final double w;
  final double h;
  final double base; // altura sobre el piso a la que "flota" (aves)
  bool pasado = false;
  _Obs(this.tipo, this.x, this.emoji, this.w, this.h, this.base);
}

class _Item {
  final _TipoPower? tipo; // null = libro coleccionable
  double x;
  final double y;
  final String emoji;
  double bob = 0;
  _Item(
      {required this.tipo,
      required this.x,
      required this.y,
      required this.emoji});
}

class _Flotante {
  final String texto;
  final double x;
  double y;
  final Color color;
  double vida = 0.9;
  _Flotante(
      {required this.texto,
      required this.x,
      required this.y,
      required this.color});
}

// ── Pintores del escenario ──
class _DunasPainter extends CustomPainter {
  final double offset;
  final Color color;
  _DunasPainter({required this.offset, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    const periodo = 260.0;
    final path = Path()..moveTo(0, size.height);
    for (double x = 0; x <= size.width + 4; x += 4) {
      final u = (x + offset) / periodo;
      final y = size.height -
          (34 + 22 * sin(u * 2 * pi) + 8 * sin(u * 2 * pi / 0.37));
      path.lineTo(x, y);
    }
    path.lineTo(size.width, size.height);
    path.close();
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(covariant _DunasPainter old) =>
      old.offset != offset || old.color != color;
}

class _PisoPainter extends CustomPainter {
  final double offset;
  final Color color;
  _PisoPainter({required this.offset, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = color);
    // Rayitas que corren para dar sensación de velocidad.
    final raya = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..strokeWidth = 2;
    const sep = 46.0;
    final desf = offset % sep;
    for (double x = -sep; x < size.width + sep; x += sep) {
      final xr = x - desf;
      canvas.drawLine(Offset(xr, 18), Offset(xr + 14, 18), raya);
      canvas.drawLine(Offset(xr + 22, 36), Offset(xr + 30, 36), raya);
    }
  }

  @override
  bool shouldRepaint(covariant _PisoPainter old) =>
      old.offset != offset || old.color != color;
}

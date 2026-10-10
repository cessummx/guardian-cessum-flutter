import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'constants.dart';
import 'student_profile.dart';
import 'ranking_api.dart';

/// Mini-juego "Atrapa al MAASO" (2-oct-2026, versión ampliada).
///
/// El venado se asoma en una cuadrícula 3×3 y hay que atraparlo antes de que
/// se esconda. Qué cambió respecto a la primera versión (30 s, un objetivo a
/// la vez, solo táctil):
///
///  · TECLADO (PC): cada celda tiene su tecla — Q W E / A S D / Z X C, o el
///    teclado numérico 7 8 9 / 4 5 6 / 1 2 3 — y la letra se ve en la
///    esquina de la celda. Espacio o Enter arrancan; Esc o P pausan.
///  · VENADO DORADO ✨ (raro, se esconde más rápido): vale triple y regala
///    un segundo de tiempo. El CACTUS 🌵 ya no solo resta un punto: quita
///    dos segundos y corta la racha.
///  · RACHA con multiplicador (×1, ×2, ×3) por aciertos seguidos. Golpear
///    una celda vacía corta la racha, para que no sirva aporrear todo.
///  · NIVELES cada 10 aciertos: el venado se esconde más rápido y, a partir
///    del nivel 3, pueden asomarse DOS cosas a la vez (una suele ser cactus).
///  · 45 segundos base, pausa, sacudida al picar cactus, panel final con
///    precisión, mejor racha y dorados atrapados; récord de la sesión.
///
/// El puntaje (puntos con multiplicador) se manda al ranking con la MISMA
/// clave de siempre. Autocontenido: sin backend, sin assets, solo emojis.
int _atrapaBest = 0;

enum _Fase { lista, jugando, pausa, fin }

enum _Tipo { venado, dorado, cactus }

class AtrapaMaasoScreen extends StatefulWidget {
  final StudentProfile perfil;
  const AtrapaMaasoScreen({super.key, required this.perfil});

  @override
  State<AtrapaMaasoScreen> createState() => _AtrapaMaasoScreenState();
}

class _AtrapaMaasoScreenState extends State<AtrapaMaasoScreen> {
  static const int _duracion = 45;
  static const List<String> _letras = ['Q', 'W', 'E', 'A', 'S', 'D', 'Z', 'X', 'C'];

  final Random _rng = Random();
  final FocusNode _foco = FocusNode();

  _Fase _fase = _Fase.lista;
  int _puntos = 0;
  int _aciertos = 0;
  int _dorados = 0;
  int _cactusPicados = 0;
  int _golpesAire = 0;
  int _racha = 0;
  int _mejorRacha = 0;
  int _tiempo = _duracion;
  final Map<int, _Tipo> _activos = {}; // celda -> qué hay asomado
  final Map<int, Color> _flash = {}; // celda -> color de destello breve
  final Map<int, Timer> _flashTimers = {};
  String _aviso = ''; // "¡Nivel 2!", "+1 s", etc.
  Timer? _avisoTimer;
  Timer? _reloj;
  Timer? _salto;
  double _shake = 0;
  Timer? _shakeTimer;
  bool _nuevoRecord = false;

  int get _nivel => 1 + _aciertos ~/ 10;
  int get _mult => 1 + min(_racha ~/ 5, 2);

  @override
  void dispose() {
    _reloj?.cancel();
    _salto?.cancel();
    _avisoTimer?.cancel();
    _shakeTimer?.cancel();
    for (final t in _flashTimers.values) {
      t.cancel();
    }
    _foco.dispose();
    super.dispose();
  }

  // ── Partida ──
  void _iniciar() {
    _reloj?.cancel();
    _salto?.cancel();
    setState(() {
      _fase = _Fase.jugando;
      _puntos = 0;
      _aciertos = 0;
      _dorados = 0;
      _cactusPicados = 0;
      _golpesAire = 0;
      _racha = 0;
      _mejorRacha = 0;
      _tiempo = _duracion;
      _activos.clear();
      _flash.clear();
      _aviso = '';
      _shake = 0;
      _nuevoRecord = false;
    });
    _reloj = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _fase != _Fase.jugando) return;
      setState(() => _tiempo--);
      if (_tiempo <= 0) _fin();
    });
    _saltar();
    _foco.requestFocus();
  }

  void _pausar() {
    if (_fase != _Fase.jugando) return;
    _salto?.cancel();
    setState(() {
      _fase = _Fase.pausa;
      _activos.clear(); // nada asomado mientras está en pausa
    });
  }

  void _reanudar() {
    if (_fase != _Fase.pausa) return;
    setState(() => _fase = _Fase.jugando);
    _saltar();
    _foco.requestFocus();
  }

  void _fin() {
    _reloj?.cancel();
    _salto?.cancel();
    _nuevoRecord = _atrapaBest > 0 && _puntos > _atrapaBest;
    if (_puntos > _atrapaBest) _atrapaBest = _puntos;
    RankingApi.enviar(
      matricula: widget.perfil.matricula,
      nombre: widget.perfil.nombreCompleto,
      juego: 'Atrapa al MAASO',
      puntaje: _puntos,
    );
    if (!mounted) return;
    setState(() {
      _fase = _Fase.fin;
      _activos.clear();
    });
  }

  // Asoma uno (o dos) objetivos, los esconde tras un rato y encadena.
  void _saltar() {
    if (_fase != _Fase.jugando) return;
    final nivel = _nivel;
    final celdas = List<int>.generate(9, (i) => i)..shuffle(_rng);
    final nuevos = <int, _Tipo>{};

    _Tipo tipoPrincipal;
    final roll = _rng.nextDouble();
    if (roll < 0.08) {
      tipoPrincipal = _Tipo.dorado;
    } else if (roll < 0.28) {
      tipoPrincipal = _Tipo.cactus;
    } else {
      tipoPrincipal = _Tipo.venado;
    }
    nuevos[celdas[0]] = tipoPrincipal;

    // Doble aparición desde el nivel 3: casi siempre un venado y un cactus,
    // para que haya que decidir, no solo reaccionar.
    if (nivel >= 3 && _rng.nextDouble() < 0.40) {
      final segundo = tipoPrincipal == _Tipo.cactus
          ? _Tipo.venado
          : (_rng.nextDouble() < 0.65 ? _Tipo.cactus : _Tipo.venado);
      nuevos[celdas[1]] = segundo;
    }

    setState(() {
      _activos
        ..clear()
        ..addAll(nuevos);
    });

    var visible = (950 - (nivel - 1) * 110).clamp(380, 950).toInt();
    if (tipoPrincipal == _Tipo.dorado) visible = (visible * 0.62).round();
    _salto = Timer(Duration(milliseconds: visible), () {
      if (!mounted || _fase != _Fase.jugando) return;
      setState(() => _activos.clear());
      _salto = Timer(const Duration(milliseconds: 170), () {
        if (!mounted) return;
        _saltar();
      });
    });
  }

  void _tocar(int i) {
    if (_fase != _Fase.jugando) return;
    final tipo = _activos[i];
    if (tipo == null) {
      // Golpe al aire: corta la racha.
      _golpesAire++;
      if (_racha > 0) _mostrarAviso('Racha perdida');
      _racha = 0;
      _destello(i, Colors.black26);
      setState(() {});
      return;
    }
    final nivelAntes = _nivel;
    setState(() {
      _activos.remove(i);
      switch (tipo) {
        case _Tipo.venado:
          _racha++;
          _aciertos++;
          _puntos += 1 * _mult;
          _destello(i, const Color(0xFF1E8E3E));
          break;
        case _Tipo.dorado:
          _racha++;
          _aciertos++;
          _dorados++;
          _puntos += 3 * _mult;
          _tiempo += 1;
          _destello(i, cessumGold);
          _mostrarAviso('✨ ¡Dorado! +1 s');
          break;
        case _Tipo.cactus:
          _cactusPicados++;
          _racha = 0;
          if (_puntos > 0) _puntos--;
          _tiempo -= 2;
          _destello(i, const Color(0xFFC62828));
          _sacudir();
          _mostrarAviso('🌵 −2 s');
          break;
      }
      if (_racha > _mejorRacha) _mejorRacha = _racha;
    });
    if (_tiempo <= 0) {
      _fin();
      return;
    }
    if (_nivel > nivelAntes) setState(() => _mostrarAviso('🔥 ¡Nivel $_nivel!'));
    // Si ya no queda nada asomado, no esperes al temporizador: siguiente ya.
    if (_activos.isEmpty && _fase == _Fase.jugando) {
      _salto?.cancel();
      _salto = Timer(const Duration(milliseconds: 140), () {
        if (!mounted) return;
        _saltar();
      });
    }
  }

  void _destello(int i, Color c) {
    _flash[i] = c;
    _flashTimers[i]?.cancel();
    _flashTimers[i] = Timer(const Duration(milliseconds: 190), () {
      if (!mounted) return;
      setState(() => _flash.remove(i));
    });
  }

  void _mostrarAviso(String t) {
    _aviso = t;
    _avisoTimer?.cancel();
    _avisoTimer = Timer(const Duration(milliseconds: 850), () {
      if (!mounted) return;
      setState(() => _aviso = '');
    });
  }

  void _sacudir() {
    _shake = 1;
    _shakeTimer?.cancel();
    _shakeTimer = Timer.periodic(const Duration(milliseconds: 30), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      _shake -= 0.12;
      if (_shake <= 0) {
        _shake = 0;
        t.cancel();
      }
      setState(() {});
    });
  }

  // ── Teclado ──
  int? _celdaDeTecla(LogicalKeyboardKey k) {
    const letras = [
      LogicalKeyboardKey.keyQ, LogicalKeyboardKey.keyW, LogicalKeyboardKey.keyE,
      LogicalKeyboardKey.keyA, LogicalKeyboardKey.keyS, LogicalKeyboardKey.keyD,
      LogicalKeyboardKey.keyZ, LogicalKeyboardKey.keyX, LogicalKeyboardKey.keyC,
    ];
    const numpad = [
      LogicalKeyboardKey.numpad7, LogicalKeyboardKey.numpad8, LogicalKeyboardKey.numpad9,
      LogicalKeyboardKey.numpad4, LogicalKeyboardKey.numpad5, LogicalKeyboardKey.numpad6,
      LogicalKeyboardKey.numpad1, LogicalKeyboardKey.numpad2, LogicalKeyboardKey.numpad3,
    ];
    final a = letras.indexOf(k);
    if (a >= 0) return a;
    final b = numpad.indexOf(k);
    if (b >= 0) return b;
    return null;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) {
      // Que mantener una tecla no cuente como varios golpes.
      if (e is KeyRepeatEvent) return KeyEventResult.handled;
      return KeyEventResult.ignored;
    }
    final k = e.logicalKey;
    final esInicio = k == LogicalKeyboardKey.space ||
        k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.numpadEnter;
    final esPausa = k == LogicalKeyboardKey.escape || k == LogicalKeyboardKey.keyP;

    if (_fase == _Fase.lista || _fase == _Fase.fin) {
      if (esInicio) {
        _iniciar();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (_fase == _Fase.pausa) {
      if (esInicio || esPausa) {
        _reanudar();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (esPausa) {
      _pausar();
      return KeyEventResult.handled;
    }
    final celda = _celdaDeTecla(k);
    if (celda != null) {
      _tocar(celda);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ── UI ──
  @override
  Widget build(BuildContext context) {
    final dx = _shake > 0 ? (_rng.nextDouble() - 0.5) * 12 * _shake : 0.0;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F1E8),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Atrapa al MAASO',
            style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          if (_fase == _Fase.jugando || _fase == _Fase.pausa)
            IconButton(
              tooltip: _fase == _Fase.pausa ? 'Seguir (Esc)' : 'Pausa (Esc)',
              icon: Icon(_fase == _Fase.pausa ? Icons.play_arrow : Icons.pause),
              onPressed: _fase == _Fase.pausa ? _reanudar : _pausar,
            ),
        ],
      ),
      body: Focus(
        focusNode: _foco,
        autofocus: true,
        onKeyEvent: _onKey,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => _foco.requestFocus(),
          child: Stack(
            children: [
              Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _stat('Puntos', '$_puntos'),
                        _stat('Tiempo', '$_tiempo', alerta: _tiempo <= 5),
                        _stat('Nivel', '$_nivel'),
                        _stat('Racha', _racha >= 5 ? '🔥 ×$_mult' : '$_racha'),
                        _stat('Mejor', _atrapaBest == 0 ? '—' : '$_atrapaBest'),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: 26,
                    child: Center(
                      child: AnimatedOpacity(
                        opacity: _aviso.isEmpty ? 0 : 1,
                        duration: const Duration(milliseconds: 120),
                        child: Text(_aviso,
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                color: cessumRed)),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      child: Transform.translate(
                        offset: Offset(dx, 0),
                        child: Center(
                          child: AspectRatio(
                            aspectRatio: 1,
                            child: GridView.count(
                              crossAxisCount: 3,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                              physics: const NeverScrollableScrollPhysics(),
                              children: [for (int i = 0; i < 9; i++) _celda(i)],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (_fase != _Fase.jugando) _panel(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stat(String etiqueta, String valor, {bool alerta = false}) {
    return Column(
      children: [
        Text(valor,
            style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: alerta ? const Color(0xFFC62828) : Colors.black87)),
        Text(etiqueta, style: const TextStyle(fontSize: 11, color: Colors.black54)),
      ],
    );
  }

  Widget _celda(int i) {
    final tipo = _activos[i];
    final activa = tipo != null;
    final esDorado = tipo == _Tipo.dorado;
    final esCactus = tipo == _Tipo.cactus;
    final flash = _flash[i];
    final Color fondo = flash != null
        ? flash.withValues(alpha: 0.55)
        : esDorado
            ? const Color(0xFFFFE9A8)
            : const Color(0xFFE8DCC0);
    return GestureDetector(
      onTap: () {
        _foco.requestFocus();
        _tocar(i);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 110),
        decoration: BoxDecoration(
          color: fondo,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: esDorado ? const Color(0xFFD4A017) : cessumGold,
              width: esDorado ? 3 : 2),
          boxShadow: esDorado
              ? [BoxShadow(color: cessumGold.withValues(alpha: 0.6), blurRadius: 14)]
              : null,
        ),
        child: Stack(
          children: [
            Positioned(
              top: 6,
              left: 8,
              child: Text(_letras[i],
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Colors.black.withValues(alpha: 0.35))),
            ),
            Center(
              child: AnimatedScale(
                scale: activa ? 1 : 0,
                duration: Duration(milliseconds: activa ? 220 : 90),
                curve: activa ? Curves.elasticOut : Curves.easeIn,
                child: Text(
                  esCactus ? '🌵' : (esDorado ? '✨🦌' : '🦌'),
                  style: TextStyle(fontSize: esDorado ? 40 : 46, height: 1),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _panel() {
    final fin = _fase == _Fase.fin;
    final pausa = _fase == _Fase.pausa;
    final intentos = _aciertos + _cactusPicados + _golpesAire;
    final precision = intentos == 0 ? 0 : (_aciertos * 100 / intentos).round();
    final titulo = pausa
        ? 'Pausa'
        : fin
            ? (_nuevoRecord ? '🏆 ¡Nuevo récord!' : '¡Tiempo!')
            : 'Atrapa al MAASO';
    return Center(
      child: Container(
        margin: const EdgeInsets.all(28),
        padding: const EdgeInsets.all(22),
        constraints: const BoxConstraints(maxWidth: 380),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(color: Colors.black26, blurRadius: 16, offset: Offset(0, 6))
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🦌', style: TextStyle(fontSize: 42)),
            const SizedBox(height: 6),
            Text(titulo,
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w800, color: cessumRed)),
            const SizedBox(height: 10),
            if (fin) ...[
              Text('$_puntos puntos',
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              _fila('Venados atrapados', '$_aciertos'),
              _fila('Dorados ✨', '$_dorados'),
              _fila('Cactus picados', '$_cactusPicados'),
              _fila('Precisión', '$precision %'),
              _fila('Mejor racha', '$_mejorRacha'),
              _fila('Nivel alcanzado', '$_nivel'),
              _fila('Mejor de la sesión', '$_atrapaBest'),
            ] else if (pausa) ...[
              const Text('Esc, Espacio o Enter para seguir.',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 14)),
            ] else ...[
              const Text(
                'Toca al venado 🦌 antes de que se esconda. El dorado ✨ vale '
                'triple y da tiempo; el cactus 🌵 quita 2 s y corta la racha.\n'
                'Aciertos seguidos: ×2 y ×3. Cada 10, sube el nivel.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13.5, height: 1.4),
              ),
              const SizedBox(height: 10),
              _teclas(),
            ],
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              ),
              onPressed: pausa ? _reanudar : _iniciar,
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

  Widget _fila(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(k, style: const TextStyle(fontSize: 13, color: Colors.black54)),
          Text(v, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _teclas() {
    Widget tecla(String t) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFF3EEE3),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.black26),
          ),
          child: Text(t,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
        );
    Widget filaTeclas(List<String> ts) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [for (final t in ts) Padding(padding: const EdgeInsets.all(2), child: tecla(t))],
        );
    return Column(
      children: [
        const Text('💻 En computadora, cada celda tiene su tecla:',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        filaTeclas(const ['Q', 'W', 'E']),
        filaTeclas(const ['A', 'S', 'D']),
        filaTeclas(const ['Z', 'X', 'C']),
        const SizedBox(height: 4),
        const Text('(o el teclado numérico 7-8-9 / 4-5-6 / 1-2-3 · Esc pausa)',
            style: TextStyle(fontSize: 11, color: Colors.black54)),
      ],
    );
  }
}

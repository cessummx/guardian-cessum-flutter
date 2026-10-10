import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'constants.dart';
import 'student_profile.dart';
import 'ranking_api.dart';

/// "El Camino del MAASO" (2-oct-2026, versión ampliada): la culebrita de
/// CESSUM, con el venado como cabeza recolectando libros por el campus.
/// Qué cambió respecto a la primera versión (swipe y flechas en pantalla):
///
///  · TECLADO (PC): flechas o W A S D giran; Espacio, P o Esc pausan; Enter
///    o Espacio arrancan. Los giros van a una COLA de dos: si giras dos veces
///    rápido (por ejemplo arriba y luego izquierda para hacer una "U"), los
///    dos se aplican en orden, uno por paso — en la versión anterior el
///    segundo giro pisaba al primero y la culebra no hacía lo que pediste.
///  · MOVIMIENTO SUAVE: los segmentos se deslizan de celda en celda en vez
///    de brincar. La cabeza mira hacia donde va.
///  · DOS MODOS: Clásico (chocar con la orilla termina) e Infinito (sales
///    por un lado y entras por el otro). Dos velocidades: Normal y Rápido.
///  · MÁS QUE LIBROS: 🎓 birrete dorado (vale 3, aparece poco tiempo),
///    ⭐ estrella (puntos ×2 durante 10 s) y 🌵 cactus fijos que van
///    apareciendo cada 5 libros (hasta 6) — chocar con uno termina.
///  · Cuenta regresiva 3-2-1 al arrancar, pausa que cubre el tablero,
///    récord de sesión y panel final con desglose.
///
/// Autocontenido: sin backend, sin assets, solo emojis y colores de CESSUM.
/// El puntaje se manda al ranking con la MISMA clave de siempre.
int _caminoBest = 0;

enum _Fase { lista, cuenta, jugando, pausa, fin }

enum _Dir { arriba, abajo, izquierda, derecha }

class CaminoMaasoScreen extends StatefulWidget {
  final StudentProfile perfil;
  const CaminoMaasoScreen({super.key, required this.perfil});

  @override
  State<CaminoMaasoScreen> createState() => _CaminoMaasoScreenState();
}

class _CaminoMaasoScreenState extends State<CaminoMaasoScreen> {
  static const int _n = 13; // tablero n×n
  final Random _rng = Random();
  final FocusNode _foco = FocusNode();

  _Fase _fase = _Fase.lista;
  bool _infinito = false;
  bool _rapido = false;

  List<Point<int>> _cuerpo = [];
  List<Point<int>> _cuerpoPrev = [];
  _Dir _dir = _Dir.derecha;
  final List<_Dir> _cola = []; // giros pendientes, máximo 2
  Point<int>? _comida;
  Point<int>? _birrete;
  Point<int>? _estrella;
  final Set<Point<int>> _cactus = {};
  int _puntaje = 0;
  int _libros = 0;
  int _birretes = 0;
  double _estrellaRestante = 0; // s con puntos ×2
  int _tickMs = 330;
  int _cuenta = 3;
  String _aviso = '';
  bool _nuevoRecord = false;

  Timer? _reloj;
  Timer? _cuentaTimer;
  Timer? _birreteTimer;
  Timer? _estrellaTablero;
  Timer? _estrellaEfecto;
  Timer? _avisoTimer;

  // Swipe: un giro por gesto, no uno por cada pixel arrastrado.
  Offset _panAcum = Offset.zero;
  bool _panConsumido = false;

  @override
  void dispose() {
    _cancelarTodo();
    _foco.dispose();
    super.dispose();
  }

  void _cancelarTodo() {
    _reloj?.cancel();
    _cuentaTimer?.cancel();
    _birreteTimer?.cancel();
    _estrellaTablero?.cancel();
    _estrellaEfecto?.cancel();
    _avisoTimer?.cancel();
  }

  // ── Partida ──
  void _iniciar() {
    _cancelarTodo();
    final c = _n ~/ 2;
    setState(() {
      _fase = _Fase.cuenta;
      _cuerpo = [Point(c, c), Point(c - 1, c), Point(c - 2, c)];
      _cuerpoPrev = List.of(_cuerpo);
      _dir = _Dir.derecha;
      _cola.clear();
      _birrete = null;
      _estrella = null;
      _cactus.clear();
      _puntaje = 0;
      _libros = 0;
      _birretes = 0;
      _estrellaRestante = 0;
      _tickMs = _rapido ? 240 : 330;
      _cuenta = 3;
      _aviso = '';
      _nuevoRecord = false;
    });
    _nuevaComida();
    _cuentaTimer = Timer.periodic(const Duration(milliseconds: 650), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_cuenta <= 1) {
        t.cancel();
        setState(() {
          _fase = _Fase.jugando;
          _cuenta = 0;
        });
        _programarTick();
      } else {
        setState(() => _cuenta--);
      }
    });
    _foco.requestFocus();
  }

  void _pausar() {
    if (_fase != _Fase.jugando) return;
    _reloj?.cancel();
    setState(() => _fase = _Fase.pausa);
  }

  void _reanudar() {
    if (_fase != _Fase.pausa) return;
    setState(() => _fase = _Fase.jugando);
    _programarTick();
    _foco.requestFocus();
  }

  void _programarTick() {
    _reloj?.cancel();
    // Más rápido conforme crece, con un piso para que siga siendo jugable.
    final base = _rapido ? 240 : 330;
    final piso = _rapido ? 100 : 130;
    _tickMs = (base - _libros * (_rapido ? 5 : 6)).clamp(piso, base).toInt();
    _reloj = Timer(Duration(milliseconds: _tickMs), _tick);
  }

  bool _libre(Point<int> p) {
    return !_cuerpo.contains(p) &&
        p != _comida &&
        p != _birrete &&
        p != _estrella &&
        !_cactus.contains(p);
  }

  Point<int> _celdaLibre({int minDistCabeza = 0}) {
    final cabeza = _cuerpo.first;
    for (int intento = 0; intento < 400; intento++) {
      final p = Point(_rng.nextInt(_n), _rng.nextInt(_n));
      if (!_libre(p)) continue;
      final d = (p.x - cabeza.x).abs() + (p.y - cabeza.y).abs();
      if (d < minDistCabeza) continue;
      return p;
    }
    // Tablero casi lleno: cualquiera libre.
    for (int y = 0; y < _n; y++) {
      for (int x = 0; x < _n; x++) {
        final p = Point(x, y);
        if (_libre(p)) return p;
      }
    }
    return cabeza;
  }

  void _nuevaComida() {
    _comida = _celdaLibre();
  }

  void _tick() {
    if (_fase != _Fase.jugando) return;
    if (_cola.isNotEmpty) _dir = _cola.removeAt(0);

    final cabeza = _cuerpo.first;
    Point<int> sig;
    switch (_dir) {
      case _Dir.arriba:
        sig = Point(cabeza.x, cabeza.y - 1);
        break;
      case _Dir.abajo:
        sig = Point(cabeza.x, cabeza.y + 1);
        break;
      case _Dir.izquierda:
        sig = Point(cabeza.x - 1, cabeza.y);
        break;
      case _Dir.derecha:
        sig = Point(cabeza.x + 1, cabeza.y);
        break;
    }

    final fuera = sig.x < 0 || sig.x >= _n || sig.y < 0 || sig.y >= _n;
    if (fuera) {
      if (_infinito) {
        sig = Point((sig.x + _n) % _n, (sig.y + _n) % _n);
      } else {
        _fin('Chocaste con la orilla');
        return;
      }
    }

    final come = sig == _comida || sig == _birrete || sig == _estrella;
    // La cola se mueve (libera su celda) salvo que coma en este paso.
    final cuerpoAChocar = come ? _cuerpo : _cuerpo.sublist(0, _cuerpo.length - 1);
    if (cuerpoAChocar.contains(sig)) {
      _fin('Chocaste contigo mismo');
      return;
    }
    if (_cactus.contains(sig)) {
      _fin('Te clavaste un cactus 🌵');
      return;
    }

    setState(() {
      _cuerpoPrev = List.of(_cuerpo);
      _cuerpo = [sig, ..._cuerpo];
      final mult = _estrellaRestante > 0 ? 2 : 1;
      if (sig == _comida) {
        _libros++;
        _puntaje += 1 * mult;
        _nuevaComida();
        _despuesDeComer();
      } else if (sig == _birrete) {
        _birretes++;
        _puntaje += 3 * mult;
        _birrete = null;
        _birreteTimer?.cancel();
        _mostrarAviso('🎓 +${3 * mult}');
      } else if (sig == _estrella) {
        _estrella = null;
        _estrellaTablero?.cancel();
        _activarEstrella();
      } else {
        _cuerpo.removeLast();
      }
    });
    _programarTick();
  }

  // Lo que puede pasar al comer un libro: aparece algo especial, o un cactus.
  void _despuesDeComer() {
    if (_libros % 5 == 0 && _cactus.length < 6) {
      final p = _celdaLibre(minDistCabeza: 3);
      if (p != _cuerpo.first) {
        _cactus.add(p);
        _mostrarAviso('🌵 ¡Cuidado, cactus nuevo!');
      }
    }
    final roll = _rng.nextDouble();
    if (_birrete == null && roll < 0.25) {
      _birrete = _celdaLibre(minDistCabeza: 2);
      _birreteTimer?.cancel();
      _birreteTimer = Timer(const Duration(seconds: 6), () {
        if (!mounted) return;
        setState(() => _birrete = null);
      });
    } else if (_estrella == null && _estrellaRestante <= 0 && roll < 0.40) {
      _estrella = _celdaLibre(minDistCabeza: 2);
      _estrellaTablero?.cancel();
      _estrellaTablero = Timer(const Duration(seconds: 7), () {
        if (!mounted) return;
        setState(() => _estrella = null);
      });
    }
  }

  void _activarEstrella() {
    _estrellaRestante = 10;
    _mostrarAviso('⭐ ¡Puntos ×2 por 10 s!');
    _estrellaEfecto?.cancel();
    _estrellaEfecto = Timer.periodic(const Duration(milliseconds: 100), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_fase != _Fase.jugando) return; // en pausa no corre
      _estrellaRestante -= 0.1;
      if (_estrellaRestante <= 0) {
        _estrellaRestante = 0;
        t.cancel();
      }
      setState(() {});
    });
  }

  void _fin(String motivo) {
    _cancelarTodo();
    _nuevoRecord = _caminoBest > 0 && _puntaje > _caminoBest;
    if (_puntaje > _caminoBest) _caminoBest = _puntaje;
    RankingApi.enviar(
      matricula: widget.perfil.matricula,
      nombre: widget.perfil.nombreCompleto,
      juego: 'El Camino del MAASO',
      puntaje: _puntaje,
    );
    if (!mounted) return;
    setState(() {
      _fase = _Fase.fin;
      _aviso = motivo;
    });
  }

  void _mostrarAviso(String t) {
    _aviso = t;
    _avisoTimer?.cancel();
    _avisoTimer = Timer(const Duration(milliseconds: 1100), () {
      if (!mounted || _fase == _Fase.fin) return;
      setState(() => _aviso = '');
    });
  }

  // ── Giros: cola de dos, sin reversa instantánea ──
  void _girar(_Dir nueva) {
    if (_fase != _Fase.jugando && _fase != _Fase.cuenta) return;
    const opuesto = {
      _Dir.arriba: _Dir.abajo,
      _Dir.abajo: _Dir.arriba,
      _Dir.izquierda: _Dir.derecha,
      _Dir.derecha: _Dir.izquierda,
    };
    final referencia = _cola.isNotEmpty ? _cola.last : _dir;
    if (nueva == referencia || opuesto[referencia] == nueva) return;
    if (_cola.length >= 2) return;
    _cola.add(nueva);
  }

  void _onPanStart(DragStartDetails d) {
    _panAcum = Offset.zero;
    _panConsumido = false;
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_panConsumido) return;
    _panAcum += d.delta;
    if (_panAcum.distance < 14) return;
    _panConsumido = true;
    if (_panAcum.dx.abs() > _panAcum.dy.abs()) {
      _girar(_panAcum.dx > 0 ? _Dir.derecha : _Dir.izquierda);
    } else {
      _girar(_panAcum.dy > 0 ? _Dir.abajo : _Dir.arriba);
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) {
      if (e is KeyRepeatEvent) return KeyEventResult.handled;
      return KeyEventResult.ignored;
    }
    final k = e.logicalKey;
    final esEnter = k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter;

    if (_fase == _Fase.lista || _fase == _Fase.fin) {
      if (esEnter || k == LogicalKeyboardKey.space) {
        _iniciar();
        return KeyEventResult.handled;
      }
      if (_fase == _Fase.lista) {
        if (k == LogicalKeyboardKey.keyI) {
          setState(() => _infinito = !_infinito);
          return KeyEventResult.handled;
        }
        if (k == LogicalKeyboardKey.keyV) {
          setState(() => _rapido = !_rapido);
          return KeyEventResult.handled;
        }
      }
      return KeyEventResult.ignored;
    }
    if (_fase == _Fase.pausa) {
      if (k == LogicalKeyboardKey.space ||
          k == LogicalKeyboardKey.keyP ||
          k == LogicalKeyboardKey.escape ||
          esEnter) {
        _reanudar();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    // Cuenta regresiva o jugando: se aceptan giros (quedan en cola).
    if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.keyW) {
      _girar(_Dir.arriba);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowDown || k == LogicalKeyboardKey.keyS) {
      _girar(_Dir.abajo);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.keyA) {
      _girar(_Dir.izquierda);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowRight || k == LogicalKeyboardKey.keyD) {
      _girar(_Dir.derecha);
      return KeyEventResult.handled;
    }
    if (_fase == _Fase.jugando &&
        (k == LogicalKeyboardKey.space ||
            k == LogicalKeyboardKey.keyP ||
            k == LogicalKeyboardKey.escape)) {
      _pausar();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ── UI ──
  @override
  Widget build(BuildContext context) {
    final enJuego = _fase == _Fase.jugando || _fase == _Fase.pausa || _fase == _Fase.cuenta;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F1E8),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('El Camino del MAASO',
            style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          if (_fase == _Fase.jugando || _fase == _Fase.pausa)
            IconButton(
              tooltip: _fase == _Fase.pausa ? 'Seguir (Espacio)' : 'Pausa (Espacio)',
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
                        _stat('Puntos', '$_puntaje'),
                        _stat('Libros', '$_libros'),
                        _stat('Largo', '${_cuerpo.length}'),
                        if (_estrellaRestante > 0)
                          _stat('⭐ ×2', '${_estrellaRestante.ceil()} s', dorado: true)
                        else
                          _stat('Mejor', _caminoBest == 0 ? '—' : '$_caminoBest'),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: 24,
                    child: Center(
                      child: AnimatedOpacity(
                        opacity: _aviso.isEmpty || _fase == _Fase.fin ? 0 : 1,
                        duration: const Duration(milliseconds: 120),
                        child: Text(_aviso,
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                                color: cessumRed)),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: GestureDetector(
                            onPanStart: _onPanStart,
                            onPanUpdate: _onPanUpdate,
                            child: Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFFE8DCC0),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                    color: _infinito
                                        ? const Color(0xFF1565C0).withValues(alpha: 0.7)
                                        : cessumGold,
                                    width: 2),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: LayoutBuilder(
                                  builder: (context, box) {
                                    final celda = box.maxWidth / _n;
                                    return Stack(
                                      children: [
                                        CustomPaint(
                                          size: Size(box.maxWidth, box.maxHeight),
                                          painter: _RejillaPainter(_n, celda),
                                        ),
                                        for (final c in _cactus)
                                          _ficha(c, celda, '🌵', 0.8),
                                        if (_comida != null)
                                          _ficha(_comida!, celda, '📚', 0.75),
                                        if (_birrete != null)
                                          _ficha(_birrete!, celda, '🎓', 0.8,
                                              resalte: cessumGold),
                                        if (_estrella != null)
                                          _ficha(_estrella!, celda, '⭐', 0.8,
                                              resalte: const Color(0xFFFFC107)),
                                        for (int i = _cuerpo.length - 1; i >= 1; i--)
                                          _segmento(i, celda),
                                        if (_cuerpo.isNotEmpty) _cabeza(celda),
                                      ],
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (enJuego) _controles(),
                  const SizedBox(height: 8),
                ],
              ),
              if (_fase == _Fase.cuenta)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 18),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text('$_cuenta',
                            style: const TextStyle(
                                fontSize: 54,
                                fontWeight: FontWeight.w900,
                                color: cessumRed)),
                      ),
                    ),
                  ),
                ),
              if (_fase == _Fase.lista || _fase == _Fase.fin || _fase == _Fase.pausa) _panel(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _ficha(Point<int> p, double celda, String emoji, double escala,
      {Color? resalte}) {
    final child = Container(
      decoration: resalte == null
          ? null
          : BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: resalte.withValues(alpha: 0.6), blurRadius: 10)],
            ),
      alignment: Alignment.center,
      child: Text(emoji, style: TextStyle(fontSize: celda * 0.62, height: 1)),
    );
    final pad = celda * (1 - escala) / 2;
    return Positioned(
      left: p.x * celda,
      top: p.y * celda,
      width: celda,
      height: celda,
      child: Padding(padding: EdgeInsets.all(pad), child: child),
    );
  }

  // En modo infinito, al cruzar la orilla un segmento pasa de un extremo al
  // otro: ahí no debe animarse (cruzaría todo el tablero), se teletransporta.
  Duration _duracionDe(int i) {
    if (i >= _cuerpoPrev.length) return Duration.zero;
    final a = _cuerpo[i];
    final b = _cuerpoPrev[i];
    final salto = (a.x - b.x).abs() + (a.y - b.y).abs();
    return salto > 1 ? Duration.zero : Duration(milliseconds: _tickMs);
  }

  Widget _segmento(int i, double celda) {
    final p = _cuerpo[i];
    final t = i / max(1, _cuerpo.length - 1);
    final color = Color.lerp(cessumGold, cessumRed.withValues(alpha: 0.85), t) ?? cessumGold;
    final escala = 0.86 - t * 0.18;
    final pad = celda * (1 - escala) / 2;
    return AnimatedPositioned(
      key: ValueKey('seg$i'),
      duration: _duracionDe(i),
      curve: Curves.linear,
      left: p.x * celda,
      top: p.y * celda,
      width: celda,
      height: celda,
      child: Padding(
        padding: EdgeInsets.all(pad),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(celda * 0.32),
            border: Border.all(color: cessumRed, width: 1.2),
          ),
        ),
      ),
    );
  }

  Widget _cabeza(double celda) {
    final p = _cuerpo.first;
    // El emoji del venado mira a la izquierda; se voltea o gira según la dirección.
    final dir = _cola.isNotEmpty ? _cola.first : _dir;
    Widget venado = Text('🦌', style: TextStyle(fontSize: celda * 0.7, height: 1));
    switch (dir) {
      case _Dir.derecha:
        venado = Transform(
          alignment: Alignment.center,
          transform: Matrix4.diagonal3Values(-1, 1, 1),
          child: venado,
        );
        break;
      case _Dir.arriba:
        venado = Transform.rotate(angle: pi / 2, child: venado);
        break;
      case _Dir.abajo:
        venado = Transform.rotate(angle: -pi / 2, child: venado);
        break;
      case _Dir.izquierda:
        break;
    }
    return AnimatedPositioned(
      key: const ValueKey('cabeza'),
      duration: _duracionDe(0),
      curve: Curves.linear,
      left: p.x * celda,
      top: p.y * celda,
      width: celda,
      height: celda,
      child: Center(child: venado),
    );
  }

  Widget _stat(String etiqueta, String valor, {bool dorado = false}) {
    return Column(
      children: [
        Text(valor,
            style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: dorado ? const Color(0xFFB8860B) : Colors.black87)),
        Text(etiqueta, style: const TextStyle(fontSize: 11, color: Colors.black54)),
      ],
    );
  }

  Widget _controles() {
    Widget boton(IconData icon, _Dir dir) {
      return IconButton(
        iconSize: 32,
        color: cessumRed,
        onPressed: () {
          _foco.requestFocus();
          _girar(dir);
        },
        icon: Icon(icon),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        boton(Icons.keyboard_arrow_up, _Dir.arriba),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            boton(Icons.keyboard_arrow_left, _Dir.izquierda),
            const SizedBox(width: 44),
            boton(Icons.keyboard_arrow_right, _Dir.derecha),
          ],
        ),
        boton(Icons.keyboard_arrow_down, _Dir.abajo),
      ],
    );
  }

  Widget _panel() {
    final fin = _fase == _Fase.fin;
    final pausa = _fase == _Fase.pausa;
    final titulo = pausa
        ? 'Pausa'
        : fin
            ? (_nuevoRecord ? '🏆 ¡Nuevo récord!' : '¡Se acabó el camino!')
            : 'El Camino del MAASO';
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(20),
        constraints: const BoxConstraints(maxWidth: 400),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: pausa ? 1 : 0.97),
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(color: Colors.black26, blurRadius: 16, offset: Offset(0, 6))
          ],
        ),
        child: SingleChildScrollView(
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
                if (_aviso.isNotEmpty)
                  Text(_aviso,
                      style: const TextStyle(fontSize: 13, color: Colors.black54)),
                const SizedBox(height: 6),
                Text('$_puntaje puntos',
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                _fila('Libros 📚', '$_libros'),
                _fila('Birretes 🎓', '$_birretes'),
                _fila('Largo final', '${_cuerpo.length}'),
                _fila('Modo', '${_infinito ? 'Infinito' : 'Clásico'} · ${_rapido ? 'Rápido' : 'Normal'}'),
                _fila('Mejor de la sesión', '$_caminoBest'),
              ] else if (pausa) ...[
                const Text('El tablero está detenido. Espacio, P o Esc para seguir.',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 14)),
              ] else ...[
                const Text(
                  'Guía al venado para recolectar libros 📚 sin chocar. El birrete 🎓 '
                  'vale 3 y dura poco; la estrella ⭐ duplica tus puntos 10 s; los '
                  'cactus 🌵 van apareciendo y no se mueven.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13.5, height: 1.4),
                ),
                const SizedBox(height: 12),
                _opcion(
                  titulo: 'Modo infinito',
                  detalle: 'Sales por un lado y entras por el otro (tecla I)',
                  valor: _infinito,
                  onChanged: (v) => setState(() => _infinito = v),
                ),
                _opcion(
                  titulo: 'Velocidad rápida',
                  detalle: 'Arranca más veloz y acelera más (tecla V)',
                  valor: _rapido,
                  onChanged: (v) => setState(() => _rapido = v),
                ),
                const SizedBox(height: 8),
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
      ),
    );
  }

  Widget _opcion(
      {required String titulo,
      required String detalle,
      required bool valor,
      required ValueChanged<bool> onChanged}) {
    return SwitchListTile(
      value: valor,
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(titulo, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
      subtitle: Text(detalle, style: const TextStyle(fontSize: 11.5)),
      onChanged: onChanged,
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
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xFFF3EEE3),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.black26),
          ),
          child: Text(t, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
        );
    return Column(
      children: [
        const Text('💻 En computadora',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            tecla('← ↑ ↓ →'),
            tecla('W A S D'),
            const Text('girar', style: TextStyle(fontSize: 11.5)),
            tecla('Espacio'),
            const Text('pausa', style: TextStyle(fontSize: 11.5)),
            tecla('Enter'),
            const Text('jugar', style: TextStyle(fontSize: 11.5)),
          ],
        ),
        const SizedBox(height: 4),
        const Text('En móvil: desliza sobre el tablero o usa las flechas.',
            style: TextStyle(fontSize: 11, color: Colors.black54)),
      ],
    );
  }
}

/// Rejilla tenue del tablero: ayuda a contar celdas y a planear la ruta.
class _RejillaPainter extends CustomPainter {
  final int n;
  final double celda;
  _RejillaPainter(this.n, this.celda);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.black.withValues(alpha: 0.05)
      ..strokeWidth = 1;
    for (int i = 1; i < n; i++) {
      final d = i * celda;
      canvas.drawLine(Offset(d, 0), Offset(d, size.height), p);
      canvas.drawLine(Offset(0, d), Offset(size.width, d), p);
    }
  }

  @override
  bool shouldRepaint(covariant _RejillaPainter old) =>
      old.n != n || old.celda != celda;
}

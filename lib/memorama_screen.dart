import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'constants.dart';
import 'student_profile.dart';
import 'ranking_api.dart';

/// Mini-juego "Memorama del Mayo" (2-oct-2026, versión ampliada).
///
/// Encuentra los pares de íconos de la región. Qué cambió respecto a la
/// primera versión (una sola cuadrícula 4×4 que arrancaba de golpe):
///
///  · TRES DIFICULTADES: Fácil 3×4 (6 pares), Normal 4×4 (8 pares),
///    Difícil 5×6 (15 pares). Pantalla de inicio para elegir, con la mejor
///    marca de cada una.
///  · TECLADO (PC): flechas mueven un cursor por el tablero, Enter o Espacio
///    voltean, H pide pista, R reinicia, Esc pausa (cubre el tablero) o
///    regresa al menú; 1/2/3 eligen dificultad en el inicio.
///  · VOLTEO 3D real de cada carta y resalte de los pares encontrados.
///  · RACHA: aciertos seguidos multiplican los puntos (×1, ×2, ×3) y se ven
///    como "🔥 ×2" en el marcador.
///  · CONTRARRELOJ opcional: con el tiempo en contra, si se acaba, pierdes.
///  · PISTAS 💡 (dos por partida): destapan todo un instante, a cambio de
///    puntos. Sirven para salir de un atorón sin quedarse pegado.
///  · Pausa con Esc, panel final con desglose del puntaje, mejor marca de la
///    sesión por dificultad.
///
/// El puntaje sigue siendo "más alto = mejor" y se manda al ranking con la
/// MISMA clave de siempre, solo si el tablero se completó (no al perder por
/// tiempo). Autocontenido: sin backend, sin assets, solo emojis y colores.
enum _Dif { facil, normal, dificil }

final Map<_Dif, int> _memBest = {}; // mejor puntaje de la sesión por dificultad

enum _Estado { oculta, visible, encontrada }

enum _Fase { inicio, jugando, pausa, gano, perdio }

class MemoramaScreen extends StatefulWidget {
  final StudentProfile perfil;
  const MemoramaScreen({super.key, required this.perfil});

  @override
  State<MemoramaScreen> createState() => _MemoramaScreenState();
}

class _MemoramaScreenState extends State<MemoramaScreen> {
  static const Color _verde = Color(0xFF1E8E3E);
  static const List<String> _iconos = [
    '🦌', '🥁', '🎓', '📚', '☀️', '🌊', '🌵', '⭐',
    '🌽', '🎺', '🪶', '🔥', '🌙', '🏛️', '🌸',
  ];

  final FocusNode _foco = FocusNode();

  _Fase _fase = _Fase.inicio;
  _Dif _dif = _Dif.normal;
  bool _contrarreloj = false;

  final List<_Carta> _cartas = [];
  int? _sel; // primera carta volteada del intento
  bool _bloqueo = false;
  int _cursor = 0;
  bool _usaTeclado = false;
  int _intentos = 0;
  int _pares = 0;
  int _racha = 0;
  int _mejorRacha = 0;
  int _bonusRacha = 0;
  int _pistas = 2;
  int _pistasUsadas = 0;
  int _segundos = 0;
  int _restante = 0;
  bool _relojCorriendo = false;
  Timer? _reloj;
  int _puntajeFinal = 0;
  bool _nuevoRecord = false;

  int get _cols => _dif == _Dif.facil ? 3 : (_dif == _Dif.normal ? 4 : 5);
  int get _filas => _dif == _Dif.facil ? 4 : (_dif == _Dif.normal ? 4 : 6);
  int get _nPares => (_cols * _filas) ~/ 2;
  int get _limite => _dif == _Dif.facil ? 60 : (_dif == _Dif.normal ? 90 : 150);
  double get _multDif => _dif == _Dif.facil ? 0.7 : (_dif == _Dif.normal ? 1.0 : 1.6);
  int get _mult => _racha >= 4 ? 3 : (_racha >= 2 ? 2 : 1);

  String _nombreDif(_Dif d) =>
      d == _Dif.facil ? 'Fácil' : (d == _Dif.normal ? 'Normal' : 'Difícil');

  @override
  void dispose() {
    _reloj?.cancel();
    _foco.dispose();
    super.dispose();
  }

  // ── Partida ──
  void _nuevo() {
    _reloj?.cancel();
    final usados = _iconos.take(_nPares).toList();
    final mazo = <_Carta>[];
    for (final ic in usados) {
      mazo.add(_Carta(ic));
      mazo.add(_Carta(ic));
    }
    mazo.shuffle(Random());
    setState(() {
      _cartas
        ..clear()
        ..addAll(mazo);
      _sel = null;
      _bloqueo = false;
      _cursor = 0;
      _intentos = 0;
      _pares = 0;
      _racha = 0;
      _mejorRacha = 0;
      _bonusRacha = 0;
      _pistas = 2;
      _pistasUsadas = 0;
      _segundos = 0;
      _restante = _limite;
      _relojCorriendo = false;
      _puntajeFinal = 0;
      _nuevoRecord = false;
      _fase = _Fase.jugando;
    });
    _foco.requestFocus();
  }

  void _arrancarReloj() {
    if (_relojCorriendo) return;
    _relojCorriendo = true;
    _reloj = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _fase != _Fase.jugando) return;
      setState(() {
        _segundos++;
        if (_contrarreloj) {
          _restante--;
          if (_restante <= 0) {
            _restante = 0;
            _perder();
          }
        }
      });
    });
  }

  void _pausar() {
    if (_fase != _Fase.jugando) return;
    setState(() => _fase = _Fase.pausa);
  }

  void _reanudar() {
    if (_fase != _Fase.pausa) return;
    setState(() => _fase = _Fase.jugando);
    _foco.requestFocus();
  }

  void _alMenu() {
    _reloj?.cancel();
    setState(() {
      _fase = _Fase.inicio;
      _cartas.clear();
    });
    _foco.requestFocus();
  }

  void _tocar(int i) {
    if (_fase != _Fase.jugando || _bloqueo) return;
    if (i < 0 || i >= _cartas.length) return;
    final c = _cartas[i];
    if (c.estado != _Estado.oculta) return;
    _arrancarReloj();

    setState(() {
      c.estado = _Estado.visible;
      _cursor = i;
    });

    if (_sel == null) {
      _sel = i;
      return;
    }
    final a = _sel!;
    if (a == i) return;
    _sel = null;
    _intentos++;

    if (_cartas[a].emoji == c.emoji) {
      _racha++;
      if (_racha > _mejorRacha) _mejorRacha = _racha;
      // El multiplicador aplica sobre los 100 puntos base del par.
      _bonusRacha += 100 * (_mult - 1);
      setState(() {
        _cartas[a].estado = _Estado.encontrada;
        c.estado = _Estado.encontrada;
        _pares++;
      });
      if (_pares == _nPares) _ganar();
    } else {
      _racha = 0;
      _bloqueo = true;
      Future.delayed(const Duration(milliseconds: 720), () {
        if (!mounted) return;
        setState(() {
          if (_cartas[a].estado == _Estado.visible) _cartas[a].estado = _Estado.oculta;
          if (c.estado == _Estado.visible) c.estado = _Estado.oculta;
          _bloqueo = false;
        });
      });
    }
  }

  void _pista() {
    if (_fase != _Fase.jugando || _bloqueo || _pistas <= 0) return;
    if (_sel != null) return; // primero cierra el intento a medias
    _arrancarReloj();
    final ocultas = <_Carta>[];
    for (final c in _cartas) {
      if (c.estado == _Estado.oculta) ocultas.add(c);
    }
    if (ocultas.isEmpty) return;
    setState(() {
      _pistas--;
      _pistasUsadas++;
      _bloqueo = true;
      for (final c in ocultas) {
        c.estado = _Estado.visible;
      }
    });
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      setState(() {
        for (final c in ocultas) {
          if (c.estado == _Estado.visible) c.estado = _Estado.oculta;
        }
        _bloqueo = false;
      });
    });
  }

  int _calcularPuntaje() {
    final base = (_nPares * 100 * _multDif).round();
    final fallos = max(0, _intentos - _nPares);
    final p = base + _bonusRacha - fallos * 12 - _segundos * 3 - _pistasUsadas * 80;
    return p.clamp(10, 100000).toInt();
  }

  void _ganar() {
    _reloj?.cancel();
    _relojCorriendo = false;
    _puntajeFinal = _calcularPuntaje();
    RankingApi.enviar(
      matricula: widget.perfil.matricula,
      nombre: widget.perfil.nombreCompleto,
      juego: 'Memorama del Mayo',
      puntaje: _puntajeFinal,
    );
    final prev = _memBest[_dif] ?? 0;
    _nuevoRecord = prev > 0 && _puntajeFinal > prev;
    if (_puntajeFinal > prev) _memBest[_dif] = _puntajeFinal;
    if (!mounted) return;
    setState(() => _fase = _Fase.gano);
  }

  void _perder() {
    _reloj?.cancel();
    _relojCorriendo = false;
    if (!mounted) return;
    setState(() => _fase = _Fase.perdio);
  }

  // ── Teclado ──
  void _mover(int dCol, int dFila) {
    if (_cartas.isEmpty) return;
    _usaTeclado = true;
    var fila = _cursor ~/ _cols;
    var col = _cursor % _cols;
    col = (col + dCol) % _cols;
    if (col < 0) col += _cols;
    fila = (fila + dFila) % _filas;
    if (fila < 0) fila += _filas;
    setState(() => _cursor = fila * _cols + col);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final repeat = e is KeyRepeatEvent;

    if (_fase == _Fase.inicio) {
      if (repeat) return KeyEventResult.handled;
      if (k == LogicalKeyboardKey.digit1 || k == LogicalKeyboardKey.numpad1) {
        setState(() => _dif = _Dif.facil);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.digit2 || k == LogicalKeyboardKey.numpad2) {
        setState(() => _dif = _Dif.normal);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.digit3 || k == LogicalKeyboardKey.numpad3) {
        setState(() => _dif = _Dif.dificil);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.keyT) {
        setState(() => _contrarreloj = !_contrarreloj);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.enter ||
          k == LogicalKeyboardKey.numpadEnter ||
          k == LogicalKeyboardKey.space) {
        _nuevo();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (_fase == _Fase.gano || _fase == _Fase.perdio) {
      if (repeat) return KeyEventResult.handled;
      if (k == LogicalKeyboardKey.enter ||
          k == LogicalKeyboardKey.numpadEnter ||
          k == LogicalKeyboardKey.space ||
          k == LogicalKeyboardKey.keyR) {
        _nuevo();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.escape) {
        _alMenu();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (_fase == _Fase.pausa) {
      if (repeat) return KeyEventResult.handled;
      if (k == LogicalKeyboardKey.escape ||
          k == LogicalKeyboardKey.space ||
          k == LogicalKeyboardKey.enter ||
          k == LogicalKeyboardKey.keyP) {
        _reanudar();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // Jugando.
    if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.keyA) {
      _mover(-1, 0);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowRight || k == LogicalKeyboardKey.keyD) {
      _mover(1, 0);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.keyW) {
      _mover(0, -1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowDown || k == LogicalKeyboardKey.keyS) {
      _mover(0, 1);
      return KeyEventResult.handled;
    }
    if (repeat) return KeyEventResult.handled;
    if (k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.numpadEnter ||
        k == LogicalKeyboardKey.space) {
      _usaTeclado = true;
      _tocar(_cursor);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.keyH) {
      _pista();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.keyR) {
      _nuevo();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.escape || k == LogicalKeyboardKey.keyP) {
      _pausar();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  String _fmt(int s) {
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final r = (s % 60).toString().padLeft(2, '0');
    return '$m:$r';
  }

  // ── UI ──
  @override
  Widget build(BuildContext context) {
    final jugando = _fase == _Fase.jugando || _fase == _Fase.pausa;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F1E8),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Memorama del Mayo',
            style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          if (jugando)
            IconButton(
              tooltip: 'Pista (H) · quedan $_pistas',
              onPressed: _pistas > 0 && _fase == _Fase.jugando ? _pista : null,
              icon: Badge(
                isLabelVisible: _pistas > 0,
                label: Text('$_pistas'),
                child: const Icon(Icons.lightbulb_outline),
              ),
            ),
          if (jugando)
            IconButton(
              tooltip: _fase == _Fase.pausa ? 'Seguir (Esc)' : 'Pausa (Esc)',
              onPressed: _fase == _Fase.pausa ? _reanudar : _pausar,
              icon: Icon(_fase == _Fase.pausa ? Icons.play_arrow : Icons.pause),
            ),
          if (jugando)
            IconButton(
                tooltip: 'Reiniciar (R)',
                onPressed: _nuevo,
                icon: const Icon(Icons.refresh)),
          if (jugando)
            IconButton(
                tooltip: 'Cambiar dificultad',
                onPressed: _alMenu,
                icon: const Icon(Icons.tune)),
        ],
      ),
      body: Focus(
        focusNode: _foco,
        autofocus: true,
        onKeyEvent: _onKey,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => _foco.requestFocus(),
          child: _fase == _Fase.inicio ? _menu() : _tablero(),
        ),
      ),
    );
  }

  Widget _menu() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🃏', style: TextStyle(fontSize: 46)),
              const SizedBox(height: 6),
              const Text('Memorama del Mayo',
                  style: TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w800, color: cessumRed)),
              const SizedBox(height: 6),
              const Text(
                'Encuentra los pares. Aciertos seguidos multiplican tus puntos; '
                'cada intento fallido y cada segundo los bajan.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13.5, height: 1.4),
              ),
              const SizedBox(height: 18),
              for (final d in _Dif.values) _opcionDif(d),
              const SizedBox(height: 8),
              SwitchListTile(
                value: _contrarreloj,
                contentPadding: EdgeInsets.zero,
                title: const Text('Contrarreloj',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                    'Si el tiempo (${_fmt(_limite)}) se acaba, pierdes. Tecla T.',
                    style: const TextStyle(fontSize: 12)),
                onChanged: (v) => setState(() => _contrarreloj = v),
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 13),
                ),
                onPressed: _nuevo,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Jugar'),
              ),
              const SizedBox(height: 14),
              _teclas(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _opcionDif(_Dif d) {
    final sel = _dif == d;
    final best = _memBest[d] ?? 0;
    final cols = d == _Dif.facil ? 3 : (d == _Dif.normal ? 4 : 5);
    final filas = d == _Dif.facil ? 4 : (d == _Dif.normal ? 4 : 6);
    final n = (d.index + 1).toString();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _dif = d),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: sel ? cessumRed.withValues(alpha: 0.08) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: sel ? cessumRed : cessumGold.withValues(alpha: 0.5),
                width: sel ? 2 : 1.2),
          ),
          child: Row(
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: sel ? cessumRed : const Color(0xFFF3EEE3),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(n,
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: sel ? Colors.white : Colors.black87)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_nombreDif(d),
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    Text('$cols × $filas · ${(cols * filas) ~/ 2} pares',
                        style: const TextStyle(fontSize: 12, color: Colors.black54)),
                  ],
                ),
              ),
              Text(best == 0 ? '—' : '🏆 $best',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, color: cessumRed)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tablero() {
    return Stack(
      children: [
        Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _stat('Pares', '$_pares/$_nPares'),
                  _stat('Intentos', '$_intentos'),
                  _stat(
                    _contrarreloj ? 'Restante' : 'Tiempo',
                    _fmt(_contrarreloj ? _restante : _segundos),
                    alerta: _contrarreloj && _restante <= 10,
                  ),
                  _stat('Racha', _racha >= 2 ? '🔥 ×$_mult' : '$_racha'),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: LayoutBuilder(
                  builder: (ctx, box) {
                    const gap = 10.0;
                    final anchoCelda = (box.maxWidth - gap * (_cols - 1)) / _cols;
                    final altoCelda = (box.maxHeight - gap * (_filas - 1)) / _filas;
                    final lado = min(anchoCelda, altoCelda);
                    final anchoTotal = lado * _cols + gap * (_cols - 1);
                    final altoTotal = lado * _filas + gap * (_filas - 1);
                    return Center(
                      child: SizedBox(
                        width: anchoTotal,
                        height: altoTotal,
                        child: GridView.count(
                          crossAxisCount: _cols,
                          mainAxisSpacing: gap,
                          crossAxisSpacing: gap,
                          physics: const NeverScrollableScrollPhysics(),
                          children: [
                            for (int i = 0; i < _cartas.length; i++) _tarjeta(i, lado),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
        if (_fase == _Fase.pausa)
          Positioned.fill(
            child: Container(
              color: const Color(0xFFF5F1E8).withValues(alpha: 0.96),
              child: _panelSimple(
                emoji: '⏸️',
                titulo: 'Pausa',
                texto: 'El tablero está cubierto. Esc, Espacio o Enter para seguir.',
                boton: 'Seguir',
                icono: Icons.play_arrow,
                accion: _reanudar,
              ),
            ),
          ),
        if (_fase == _Fase.gano) _panelVictoria(),
        if (_fase == _Fase.perdio)
          _panelSimple(
            emoji: '⏰',
            titulo: 'Se acabó el tiempo',
            texto: 'Encontraste $_pares de $_nPares pares en $_intentos intentos.\n'
                'Vuelve a intentarlo o quita el contrarreloj en el menú.',
            boton: 'Jugar de nuevo',
            icono: Icons.refresh,
            accion: _nuevo,
            secundario: 'Menú',
            accionSecundaria: _alMenu,
          ),
      ],
    );
  }

  Widget _stat(String etiqueta, String valor, {bool alerta = false}) {
    return Column(
      children: [
        Text(valor,
            style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: alerta ? const Color(0xFFC62828) : cessumRed)),
        Text(etiqueta,
            style: const TextStyle(fontSize: 11, color: Colors.black54)),
      ],
    );
  }

  Widget _tarjeta(int i, double lado) {
    final c = _cartas[i];
    final abierta = c.estado != _Estado.oculta;
    final encontrada = c.estado == _Estado.encontrada;
    final conCursor = _usaTeclado && _cursor == i && _fase == _Fase.jugando;
    final fontSize = (lado * 0.48).clamp(18.0, 40.0).toDouble();
    return GestureDetector(
      onTap: () {
        _usaTeclado = false;
        _foco.requestFocus();
        _tocar(i);
      },
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: abierta ? 1 : 0),
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInOut,
        builder: (ctx, t, _) {
          // t: 0 = dorso, 1 = frente. La carta gira sobre su eje vertical y a
          // medio giro cambia de cara, así nunca se ve el frente al revés.
          final angulo = t * pi;
          final muestraFrente = t > 0.5;
          final m = Matrix4.identity()
            ..setEntry(3, 2, 0.0012)
            ..rotateY(angulo);
          return Transform(
            alignment: Alignment.center,
            transform: m,
            child: muestraFrente
                ? Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()..rotateY(pi),
                    child: _cara(frente: true, c: c, encontrada: encontrada,
                        conCursor: conCursor, fontSize: fontSize),
                  )
                : _cara(frente: false, c: c, encontrada: false,
                    conCursor: conCursor, fontSize: fontSize),
          );
        },
      ),
    );
  }

  Widget _cara(
      {required bool frente,
      required _Carta c,
      required bool encontrada,
      required bool conCursor,
      required double fontSize}) {
    final Color borde = conCursor
        ? const Color(0xFF1565C0)
        : encontrada
            ? _verde
            : (frente ? cessumGold : cessumRed);
    return Container(
      decoration: BoxDecoration(
        color: frente
            ? (encontrada ? const Color(0xFFE8F5E9) : Colors.white)
            : cessumRed,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borde, width: conCursor ? 3.5 : (encontrada ? 2.5 : 1.5)),
        boxShadow: conCursor
            ? [BoxShadow(color: borde.withValues(alpha: 0.45), blurRadius: 10)]
            : null,
      ),
      alignment: Alignment.center,
      child: frente
          ? Text(c.emoji, style: TextStyle(fontSize: fontSize))
          : Icon(Icons.pets, color: Colors.white.withValues(alpha: 0.9), size: fontSize * 0.8),
    );
  }

  Widget _panelSimple({
    required String emoji,
    required String titulo,
    required String texto,
    required String boton,
    required IconData icono,
    required VoidCallback accion,
    String? secundario,
    VoidCallback? accionSecundaria,
  }) {
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
            Text(emoji, style: const TextStyle(fontSize: 40)),
            const SizedBox(height: 8),
            Text(titulo,
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w800, color: cessumRed)),
            const SizedBox(height: 8),
            Text(texto, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cessumRed,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                  ),
                  onPressed: accion,
                  icon: Icon(icono),
                  label: Text(boton),
                ),
                if (secundario != null)
                  OutlinedButton(
                    onPressed: accionSecundaria,
                    style: OutlinedButton.styleFrom(foregroundColor: cessumRed),
                    child: Text(secundario),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _panelVictoria() {
    final best = _memBest[_dif] ?? 0;
    final fallos = max(0, _intentos - _nPares);
    return Center(
      child: Container(
        margin: const EdgeInsets.all(28),
        padding: const EdgeInsets.all(22),
        constraints: const BoxConstraints(maxWidth: 400),
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
            const Text('🦌🎉', style: TextStyle(fontSize: 40)),
            const SizedBox(height: 8),
            Text(_nuevoRecord ? '🏆 ¡Nuevo récord!' : '¡Lo lograste!',
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w800, color: cessumRed)),
            const SizedBox(height: 4),
            Text('${_nombreDif(_dif)} · ${_fmt(_segundos)} · $_intentos intentos',
                style: const TextStyle(fontSize: 12.5, color: Colors.black54)),
            const SizedBox(height: 12),
            Text('$_puntajeFinal puntos',
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            _fila('Pares × 100 × ${_multDif.toStringAsFixed(1)}',
                '+${(_nPares * 100 * _multDif).round()}'),
            if (_bonusRacha > 0) _fila('Bonus por rachas (mejor ×$_mejorRachaMult)', '+$_bonusRacha'),
            if (fallos > 0) _fila('Intentos fallidos ($fallos × 12)', '−${fallos * 12}'),
            _fila('Tiempo ($_segundos s × 3)', '−${_segundos * 3}'),
            if (_pistasUsadas > 0) _fila('Pistas ($_pistasUsadas × 80)', '−${_pistasUsadas * 80}'),
            if (best > 0) ...[
              const SizedBox(height: 6),
              Text('Mejor marca en ${_nombreDif(_dif)}: $best',
                  style: const TextStyle(fontSize: 12, color: Colors.black54)),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cessumRed,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                  ),
                  onPressed: _nuevo,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Jugar de nuevo'),
                ),
                OutlinedButton(
                  onPressed: _alMenu,
                  style: OutlinedButton.styleFrom(foregroundColor: cessumRed),
                  child: const Text('Cambiar dificultad'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  int get _mejorRachaMult => _mejorRacha >= 4 ? 3 : (_mejorRacha >= 2 ? 2 : 1);

  Widget _fila(String k, String v) {
    final negativo = v.startsWith('−');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
              child: Text(k,
                  style: const TextStyle(fontSize: 12.5, color: Colors.black54))),
          const SizedBox(width: 8),
          Text(v,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: negativo ? const Color(0xFFC62828) : _verde)),
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
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
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
            const Text('mover', style: TextStyle(fontSize: 11.5)),
            tecla('Enter'),
            tecla('Espacio'),
            const Text('voltear', style: TextStyle(fontSize: 11.5)),
            tecla('H'),
            const Text('pista', style: TextStyle(fontSize: 11.5)),
            tecla('R'),
            const Text('reiniciar', style: TextStyle(fontSize: 11.5)),
            tecla('Esc'),
            const Text('pausa', style: TextStyle(fontSize: 11.5)),
          ],
        ),
      ],
    );
  }
}

class _Carta {
  final String emoji;
  _Estado estado;
  _Carta(this.emoji) : estado = _Estado.oculta;
}

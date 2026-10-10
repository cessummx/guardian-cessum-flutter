import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'student_profile.dart';

/// Calculadora de promedio del alumno.
///
/// (8-sep) REESCRITA. La versión anterior era una hoja de cálculo en blanco:
/// el alumno tenía que teclear cada materia y cada calificación, elegía entre
/// dos escalas abstractas (0–100 y 0–10) que no son la de CESSUM, y obtenía
/// dos promedios sin ningún referente. Nada le decía lo único que de verdad
/// quiere saber cuando abre esta pantalla: si va a alcanzar la titulación por
/// Excelencia Académica.
///
/// Tres cambios de fondo:
///  1. Trae sus calificaciones reales del Guardián (mis_calificaciones), así
///     que empieza con su expediente cargado y solo simula lo que falta.
///  2. Usa la escala institucional: el Reglamento (Art. 48) fija de 6 a 10 y
///     la mínima aprobatoria en 7. Lo que esté abajo de 7 se marca como
///     reprobado, porque una reprobada tumba la Excelencia aunque el promedio
///     dé.
///  3. Compara contra los dos umbrales que importan y dice cuánto falta:
///     Excelencia Académica (9.5) y mención honorífica (9.0).
class CalculadoraPromedioScreen extends StatefulWidget {
  const CalculadoraPromedioScreen({super.key});

  @override
  State<CalculadoraPromedioScreen> createState() =>
      _CalculadoraPromedioScreenState();
}

class _Fila {
  final TextEditingController nombre = TextEditingController();
  final TextEditingController calif = TextEditingController();
  final TextEditingController creditos = TextEditingController();

  /// Verdadero cuando el renglón vino del expediente y no lo escribió el
  /// alumno. Sirve para distinguir lo que ya está calificado de lo que está
  /// simulando; sigue siendo editable, porque simular «¿y si en esta saco 9?»
  /// es justo para lo que se usa la pantalla.
  bool delExpediente = false;

  void dispose() {
    nombre.dispose();
    calif.dispose();
    creditos.dispose();
  }
}

class _CalculadoraPromedioScreenState
    extends State<CalculadoraPromedioScreen> {
  static const double kAprobatoria = 7;
  static const double kExcelencia = 9.5;
  static const double kMencion = 9;

  final List<_Fila> _filas = [];
  double _escala = 10;

  final TextEditingController _faltan = TextEditingController();

  bool _cargando = true;
  String _aviso = '';
  String _programa = '';
  int _delExpediente = 0;

  @override
  void initState() {
    super.initState();
    _cargarExpediente();
  }

  @override
  void dispose() {
    for (final f in _filas) {
      f.dispose();
    }
    _faltan.dispose();
    super.dispose();
  }

  void _filasEnBlanco(int n) {
    for (var i = 0; i < n; i++) {
      _filas.add(_Fila());
    }
  }

  /// Trae las calificaciones ya registradas. Si algo falla no se bloquea la
  /// pantalla: la calculadora sigue sirviendo en blanco, que es como
  /// funcionaba antes.
  Future<void> _cargarExpediente() async {
    try {
      final perfil = await StudentProfile.load();
      final mat = perfil?.matricula.trim() ?? '';
      if (mat.isEmpty) {
        if (!mounted) return;
        setState(() {
          _cargando = false;
          _aviso = 'Captura tus materias a mano: no encontré tu matrícula '
              'en esta sesión.';
          _filasEnBlanco(3);
        });
        return;
      }
      _programa = perfil?.programa.trim() ?? '';
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'mis_calificaciones',
        'matricula': mat,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 60));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] != true) {
        setState(() {
          _cargando = false;
          _aviso = 'Captura tus materias a mano: no pude leer tu expediente.';
          _filasEnBlanco(3);
        });
        return;
      }
      final materias = ((data['materias'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      var contadas = 0;
      for (final m in materias) {
        final cal = double.tryParse(
            '${m['calificacion'] ?? ''}'.trim().replaceAll(',', '.'));
        if (cal == null) continue; // sin nota todavía: no entra al promedio
        final f = _Fila()
          ..delExpediente = true
          ..nombre.text = '${m['materia'] ?? ''}'.trim()
          ..calif.text = _limpio(cal);
        _filas.add(f);
        contadas++;
      }
      setState(() {
        _delExpediente = contadas;
        _cargando = false;
        if (contadas == 0) {
          _aviso = 'Todavía no tienes calificaciones registradas. '
              'Captura las que quieras simular.';
          _filasEnBlanco(3);
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _aviso = 'Captura tus materias a mano: no pude leer tu expediente.';
        _filasEnBlanco(3);
      });
    }
  }

  String _limpio(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  double? _num(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', '.'));

  List<double> get _califs =>
      _filas.map((f) => _num(f.calif)).whereType<double>().toList();

  int get _reprobadas =>
      _escala == 10 ? _califs.where((c) => c < kAprobatoria).length : 0;

  double? get _promedioSimple {
    final cs = _califs;
    if (cs.isEmpty) return null;
    return cs.reduce((a, b) => a + b) / cs.length;
  }

  double? get _promedioPonderado {
    double sumaCr = 0, sumaPond = 0;
    for (final f in _filas) {
      final c = _num(f.calif);
      final cr = _num(f.creditos);
      if (c == null || cr == null || cr <= 0) continue;
      sumaCr += cr;
      sumaPond += c * cr;
    }
    if (sumaCr <= 0) return null;
    return sumaPond / sumaCr;
  }

  String _fmt(double? v) => v == null ? '—' : v.toStringAsFixed(2);

  /// Qué promedio hace falta en las materias restantes para llegar a [meta].
  /// Devuelve null si no hay datos suficientes.
  double? _necesarioPara(double meta) {
    final cs = _califs;
    final faltan = int.tryParse(_faltan.text.trim());
    if (cs.isEmpty || faltan == null || faltan <= 0) return null;
    final suma = cs.fold<double>(0, (a, b) => a + b);
    return (meta * (cs.length + faltan) - suma) / faltan;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Calculadora de promedio'),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : ListView(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
              children: [
                _encabezado(),
                const SizedBox(height: 14),
                _tarjetaTitulacion(),
                const SizedBox(height: 14),
                _selectorEscala(),
                const SizedBox(height: 10),
                ...List.generate(_filas.length, (i) => _filaWidget(i)),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Agregar materia'),
                    style: TextButton.styleFrom(foregroundColor: cessumRed),
                    onPressed: () => setState(() => _filas.add(_Fila())),
                  ),
                ),
                const SizedBox(height: 12),
                _tarjetaProyeccion(),
                const SizedBox(height: 14),
                _notaReglamento(),
              ],
            ),
    );
  }

  /// El promedio, dicho como respuesta y no como celda de una tabla.
  Widget _encabezado() {
    final simple = _promedioSimple;
    final pond = _promedioPonderado;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: CC.goldBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _programa.isEmpty ? 'Tu promedio' : 'Tu promedio · $_programa',
            style: TextStyle(fontSize: 12.5, color: cessumMuted(context)),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(_fmt(simple),
                  style: const TextStyle(
                      fontSize: 40,
                      height: 1,
                      fontWeight: FontWeight.w800,
                      color: cessumRed)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _califs.isEmpty
                      ? 'sin materias capturadas'
                      : 'con ${_califs.length} materia'
                          '${_califs.length == 1 ? '' : 's'}'
                          '${_delExpediente > 0 ? ' · $_delExpediente de tu expediente' : ''}',
                  style: TextStyle(fontSize: 12.5, color: cessumMuted(context)),
                ),
              ),
            ],
          ),
          if (pond != null) ...[
            const SizedBox(height: 8),
            Text('Ponderado por créditos: ${_fmt(pond)}',
                style: TextStyle(fontSize: 12.5, color: cessumMuted(context))),
          ],
          if (_aviso.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(_aviso,
                style: const TextStyle(fontSize: 12, color: Color(0xFF8A6D1F))),
          ],
        ],
      ),
    );
  }

  /// Lo que el alumno viene a preguntar: si le alcanza para titularse por
  /// Excelencia Académica. Se responde con los dos umbrales del Reglamento y
  /// con la condición que casi nadie recuerda: una sola reprobada los anula.
  Widget _tarjetaTitulacion() {
    final prom = _promedioSimple;
    final rep = _reprobadas;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CC.goldCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: CC.goldBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Hacia dónde vas',
              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          _umbral('Excelencia Académica', kExcelencia, prom, rep),
          const SizedBox(height: 8),
          _umbral('Mención honorífica', kMencion, prom, rep),
          if (rep > 0) ...[
            const SizedBox(height: 10),
            Text(
                rep == 1
                    ? 'Tienes 1 materia abajo de 7. Mientras no la acredites, '
                        'ninguna de las dos vías procede aunque el promedio alcance.'
                    : 'Tienes $rep materias abajo de 7. Mientras no las acredites, '
                        'ninguna de las dos vías procede aunque el promedio alcance.',
                style: const TextStyle(
                    fontSize: 12, height: 1.35, color: Color(0xFFB3261E))),
          ],
        ],
      ),
    );
  }

  Widget _umbral(String nombre, double meta, double? prom, int rep) {
    final falta = _necesarioPara(meta);
    String detalle;
    Color color;
    if (prom == null) {
      detalle = 'captura tus calificaciones';
      color = cessumMuted(context);
    } else if (prom >= meta && rep == 0) {
      detalle = 'vas dentro';
      color = const Color(0xFF1E8E3E);
    } else if (falta == null) {
      final dif = meta - prom;
      detalle = dif <= 0
          ? 'el promedio alcanza'
          : 'te faltan ${dif.toStringAsFixed(2)} de promedio';
      color = cessumMuted(context);
    } else if (falta <= 0) {
      detalle = 'ya no puedes bajar de la meta';
      color = const Color(0xFF1E8E3E);
    } else if (falta > _escala) {
      detalle = 'fuera de alcance con las materias que faltan';
      color = const Color(0xFFB3261E);
    } else {
      detalle =
          'necesitas ${falta.toStringAsFixed(2)} en las que te faltan';
      color = cessumRed;
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 46,
          child: Text(meta.toStringAsFixed(1),
              style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w800, color: color)),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(nombre,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
              Text(detalle,
                  style: TextStyle(fontSize: 12, color: color, height: 1.3)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _selectorEscala() {
    return Row(
      children: [
        Text('Escala', style: TextStyle(color: cessumMuted(context))),
        const SizedBox(width: 10),
        ChoiceChip(
          label: const Text('CESSUM (6 – 10)'),
          selected: _escala == 10,
          selectedColor: cessumGold.withValues(alpha: 0.3),
          onSelected: (_) => setState(() => _escala = 10),
        ),
        const SizedBox(width: 8),
        ChoiceChip(
          label: const Text('Puntos (0 – 100)'),
          selected: _escala == 100,
          selectedColor: cessumGold.withValues(alpha: 0.3),
          onSelected: (_) => setState(() => _escala = 100),
        ),
      ],
    );
  }

  Widget _filaWidget(int i) {
    final f = _filas[i];
    final cal = _num(f.calif);
    final reprobada = _escala == 10 && cal != null && cal < kAprobatoria;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 5,
            child: TextField(
              controller: f.nombre,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                labelText: 'Materia',
                isDense: true,
                filled: f.delExpediente,
                fillColor: f.delExpediente ? CC.goldSoft : null,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 2,
            child: TextField(
              controller: f.calif,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: reprobada ? const Color(0xFFB3261E) : null),
              decoration: InputDecoration(
                labelText: 'Calif.',
                isDense: true,
                border: const OutlineInputBorder(),
                errorText: reprobada ? 'reprobada' : null,
                errorStyle: const TextStyle(fontSize: 10, height: 0.9),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 2,
            child: TextField(
              controller: f.creditos,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                  labelText: 'Créd.',
                  isDense: true,
                  border: OutlineInputBorder()),
            ),
          ),
          IconButton(
            tooltip: 'Quitar',
            icon: const Icon(Icons.close, size: 18, color: Colors.redAccent),
            onPressed: _filas.length <= 1
                ? null
                : () => setState(() {
                      final quitada = _filas.removeAt(i);
                      if (quitada.delExpediente && _delExpediente > 0) {
                        _delExpediente--;
                      }
                      quitada.dispose();
                    }),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaProyeccion() {
    final faltan = int.tryParse(_faltan.text.trim());
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cessumFaint(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Lo que te falta por cursar',
              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
              'Escribe cuántas materias te faltan y arriba verás qué promedio '
              'necesitas en ellas para cada meta.',
              style: TextStyle(
                  fontSize: 12, height: 1.35, color: cessumMuted(context))),
          const SizedBox(height: 12),
          SizedBox(
            width: 220,
            child: TextField(
              controller: _faltan,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                  labelText: 'Materias por cursar',
                  isDense: true,
                  border: OutlineInputBorder()),
            ),
          ),
          if (faltan != null && faltan > 0 && _califs.isNotEmpty) ...[
            const SizedBox(height: 12),
            _lineaMeta('Para 7.0 (acreditar)', kAprobatoria),
            _lineaMeta('Para 9.0 (mención honorífica)', kMencion),
            _lineaMeta('Para 9.5 (Excelencia Académica)', kExcelencia),
          ],
        ],
      ),
    );
  }

  Widget _lineaMeta(String etiqueta, double meta) {
    final n = _necesarioPara(meta);
    String valor;
    Color color = cessumRed;
    if (n == null) {
      valor = '—';
      color = cessumMuted(context);
    } else if (n <= 0) {
      valor = 'ya está';
      color = const Color(0xFF1E8E3E);
    } else if (n > _escala) {
      valor = 'no alcanza';
      color = const Color(0xFFB3261E);
    } else {
      valor = n.toStringAsFixed(2);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
              child: Text(etiqueta, style: const TextStyle(fontSize: 12.5))),
          Text(valor,
              style: TextStyle(
                  fontSize: 14.5, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }

  Widget _notaReglamento() {
    return Text(
      'El Reglamento Institucional fija la escala de 6 a 10 y la calificación '
      'mínima aprobatoria en 7 (Art. 48). La Excelencia Académica y la mención '
      'honorífica piden además haber cursado el programa sin interrupciones de '
      'ciclo, algo que esta calculadora no verifica.',
      style: TextStyle(fontSize: 11.5, height: 1.4, color: cessumMuted(context)),
    );
  }
}

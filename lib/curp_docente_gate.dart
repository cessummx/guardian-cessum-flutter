// DOCENTE: candado de CURP (jul-2026). La autoridad educativa (SIGA) exige
// la CURP de cada docente. Esta pantalla se presenta al entrar si el docente
// no tiene CURP registrada (y su contrato tampoco la tiene): debe capturarla
// antes de continuar. Guarda también la escolaridad.
// Los administradores pueden cerrarla (permitirSalir).
//
// (ago-17) VALIDACIÓN IGUAL A LA DEL SERVIDOR. Antes aquí solo se revisaba
// la forma gruesa (^[A-Z]{4}[0-9]{6}[A-Z]{6}[A-Z0-9]{2}$) mientras el backend
// exige además H/M en la posición 11, mes y día posibles, y el DÍGITO
// VERIFICADOR de RENAPO. Resultado: un dedazo pasaba el botón, viajaba al
// servidor y volvía como error rojo sin explicación útil. Ahora el mismo
// cálculo corre aquí y el motivo se ve DEBAJO del campo mientras teclea.
// Además el filtro de teclado bloqueaba la Ñ, que es válida en una CURP
// (apellidos como Núñez o Peña): ya se admite.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

class CurpDocenteGate extends StatefulWidget {
  final String correo;
  final String nombre;
  final bool permitirSalir;
  const CurpDocenteGate({
    super.key,
    required this.correo,
    this.nombre = '',
    this.permitirSalir = false,
  });

  @override
  State<CurpDocenteGate> createState() => _CurpDocenteGateState();
}

/// Resultado de validar una CURP: si sirve y, si no, por qué.
class CurpChequeo {
  final bool ok;
  final String motivo;
  const CurpChequeo(this.ok, this.motivo);
}

/// Mismo criterio que `_curpValidaDetalle_` en Code.gs. Si se cambia allá,
/// cambiar aquí: son los dos extremos de la misma regla.
CurpChequeo revisarCurp(String entrada) {
  final curp = entrada.trim().toUpperCase();
  if (curp.isEmpty) return const CurpChequeo(false, 'Escribe tu CURP.');
  if (curp.length < 18) {
    return CurpChequeo(false, 'Faltan ${18 - curp.length} caracteres.');
  }
  if (curp.length > 18) {
    return const CurpChequeo(false, 'Son 18 caracteres exactos.');
  }
  final forma = RegExp(r'^[A-ZÑ]{4}[0-9]{6}[HM][A-ZÑ]{5}[0-9A-ZÑ][0-9]$');
  if (!forma.hasMatch(curp)) {
    // Diagnóstico fino, para que el docente sepa dónde mirar.
    if (!RegExp(r'^[A-ZÑ]{4}').hasMatch(curp)) {
      return const CurpChequeo(false, 'Las primeras 4 deben ser letras.');
    }
    if (!RegExp(r'^[A-ZÑ]{4}[0-9]{6}').hasMatch(curp)) {
      return const CurpChequeo(
          false, 'Del carácter 5 al 10 va tu fecha de nacimiento: AAMMDD.');
    }
    final sexo = curp.substring(10, 11);
    if (sexo != 'H' && sexo != 'M') {
      return const CurpChequeo(
          false, 'El carácter 11 debe ser H o M (sexo).');
    }
    if (!RegExp(r'^[0-9]$').hasMatch(curp.substring(17))) {
      return const CurpChequeo(false, 'El último carácter debe ser un número.');
    }
    return const CurpChequeo(false, 'El formato no corresponde a una CURP.');
  }
  // La fecha va AAMMDD en los caracteres 5 a 10: año 5-6, mes 7-8, día 9-10.
  final mes = int.tryParse(curp.substring(6, 8)) ?? 0;
  final dia = int.tryParse(curp.substring(8, 10)) ?? 0;
  if (mes < 1 || mes > 12) {
    return const CurpChequeo(false, 'El mes de nacimiento no existe.');
  }
  if (dia < 1 || dia > 31) {
    return const CurpChequeo(false, 'El día de nacimiento no existe.');
  }
  const dic = '0123456789ABCDEFGHIJKLMNÑOPQRSTUVWXYZ';
  var suma = 0;
  for (var i = 0; i < 17; i++) {
    final v = dic.indexOf(curp[i]);
    if (v < 0) return const CurpChequeo(false, 'Tiene un carácter no válido.');
    suma += v * (18 - i);
  }
  final dv = (10 - (suma % 10)) % 10;
  if (dv != int.parse(curp[17])) {
    return const CurpChequeo(false,
        'El último dígito no cuadra con el resto: revisa letra por letra.');
  }
  return const CurpChequeo(true, '');
}

class _CurpDocenteGateState extends State<CurpDocenteGate> {
  final _curpCtrl = TextEditingController();
  String _escolaridad = '';
  bool _guardando = false;

  CurpChequeo get _chequeo => revisarCurp(_curpCtrl.text);
  bool get _curpValida => _chequeo.ok;
  bool get _listo => _curpValida && _escolaridad.isNotEmpty;

  @override
  void dispose() {
    _curpCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final curp = _curpCtrl.text.trim().toUpperCase();
    final chk = revisarCurp(curp);
    if (!chk.ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.red,
        content: Text(chk.motivo),
      ));
      return;
    }
    setState(() => _guardando = true);
    try {
      final resp = await http
          .get(Uri.parse('$guardianUrl?accion=docente_curp_guardar'
              '&correo=${Uri.encodeComponent(widget.correo)}'
              '&curp=${Uri.encodeComponent(curp)}'
              '&escolaridad=${Uri.encodeComponent(_escolaridad)}'))
          .timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          backgroundColor: Color(0xFF1E8E3E),
          content: Text('CURP registrada. ¡Gracias!'),
        ));
        Navigator.pop(context, true);
      } else {
        setState(() => _guardando = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text(data['error']?.toString() ?? 'No se pudo guardar.'),
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _guardando = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: Colors.red,
          content: Text('Error: $e'),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final chk = _chequeo;
    final escrito = _curpCtrl.text.isNotEmpty;
    return PopScope(
      canPop: widget.permitirSalir,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !widget.permitirSalir) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            backgroundColor: cessumRed,
            content: Text('Registra tu CURP para continuar.'),
          ));
        }
      },
      child: Scaffold(
        backgroundColor: cessumBg(context),
        appBar: AppBar(
          backgroundColor: cessumRed,
          foregroundColor: Colors.white,
          automaticallyImplyLeading: widget.permitirSalir,
          title: const Text('Registro de CURP',
              style: TextStyle(fontWeight: FontWeight.w800)),
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cessumRed.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.badge_outlined, color: cessumRed, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text('Necesitamos tu CURP',
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                                color: cessumRed)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'CESSUM debe reportar la plantilla docente a la autoridad '
                    'educativa (SIGA · SEC Sonora), y la CURP es un dato '
                    'obligatorio de ese reporte. Solo se usa para fines '
                    'oficiales. Te toma un minuto y no se te volverá a pedir.',
                    style: TextStyle(fontSize: 12.5, height: 1.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            if (widget.nombre.isNotEmpty) ...[
              Text(widget.nombre,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
            ],
            TextField(
              controller: _curpCtrl,
              maxLength: 18,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                // La Ñ es válida en una CURP (Núñez, Peña): no se filtra.
                FilteringTextInputFormatter.allow(RegExp(r'[a-zA-ZñÑ0-9]')),
                UpperCaseTextFormatter(),
              ],
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'CURP (18 caracteres)',
                hintText: 'Ej. XXXX000000HXXXXX00',
                border: const OutlineInputBorder(),
                errorText: (escrito && !chk.ok) ? chk.motivo : null,
                helperText: chk.ok ? 'CURP correcta.' : null,
                helperStyle: const TextStyle(
                    color: Color(0xFF1E8E3E), fontWeight: FontWeight.w600),
                suffixIcon: !escrito
                    ? null
                    : Icon(
                        chk.ok ? Icons.check_circle : Icons.error_outline,
                        color:
                            chk.ok ? const Color(0xFF1E8E3E) : Colors.red,
                      ),
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _escolaridad.isEmpty ? null : _escolaridad,
              decoration: const InputDecoration(
                labelText: 'Máximo grado de estudios',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: '1', child: Text('Licenciatura')),
                DropdownMenuItem(value: '2', child: Text('Maestría')),
                DropdownMenuItem(value: '3', child: Text('Doctorado')),
                DropdownMenuItem(value: '4', child: Text('Otro')),
              ],
              onChanged: (v) => setState(() => _escolaridad = v ?? ''),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _guardando || !_listo ? null : _guardar,
                icon: _guardando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.save),
                label: Text(_guardando ? 'Guardando…' : 'Guardar mi CURP'),
              ),
            ),
            if (_curpValida && _escolaridad.isEmpty) ...[
              const SizedBox(height: 8),
              Text('Falta elegir tu máximo grado de estudios.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: cessumMuted(context))),
            ],
            const SizedBox(height: 10),
            Text(
              '¿No recuerdas tu CURP? Consúltala en gob.mx/curp con tu nombre '
              'y fecha de nacimiento.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, color: cessumMuted(context)),
            ),
          ],
        ),
      ),
    );
  }
}

// Convierte lo tecleado a MAYÚSCULAS al vuelo.
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}

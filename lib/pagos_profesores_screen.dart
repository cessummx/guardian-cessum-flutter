// Pagos a profesores — (4-oct-2026) UNIFICADA con «Pagos a docentes».
//
// Había dos pantallas para lo mismo: esta (que abría el Centro de mando) y PagosDocentesScreen (que abría el menú de
// administración). Pedían las mismas rutas (pagos_prof_pendientes, pagos_prof_historial, pagar_profesor), pero cada una
// tenía cosas que a la otra le faltaban: aquí se podía adjuntar el depósito después; allá, descartar un pendiente y
// eliminar un pago mal registrado. Dependiendo de por dónde entrara, el administrador veía una u otra.
// Ahora esta clase solo abre PagosDocentesScreen, que reúne todo. Se conserva el nombre para no tocar a quien la llama.
import 'package:flutter/material.dart';

import 'pagos_docentes_screen.dart';

class PagosProfesoresScreen extends StatelessWidget {
  const PagosProfesoresScreen({super.key});

  @override
  Widget build(BuildContext context) => const PagosDocentesScreen();
}

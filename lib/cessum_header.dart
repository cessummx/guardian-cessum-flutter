import 'package:flutter/material.dart';

import 'constants.dart';

/// AppBar de marca CESSUM: fondo blanco, el logo (o un título) y una franja
/// degradada rojo→dorado en la base. Úsalo como `appBar: const CessumAppBar()`
/// o `CessumAppBar(titulo: 'Mi progreso')`.
class CessumAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String? titulo;
  final List<Widget>? actions;
  final Widget? leading;

  const CessumAppBar({super.key, this.titulo, this.actions, this.leading});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 3);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.white,
      foregroundColor: cessumRed,
      elevation: 1,
      surfaceTintColor: Colors.white,
      leading: leading,
      centerTitle: false,
      title: titulo != null
          ? Text(
              titulo!,
              style: const TextStyle(
                color: cessumRed,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            )
          : Image.asset('assets/images/logo.png', height: 30),
      actions: actions,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(3),
        child: Container(
          height: 3,
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [cessumRed, cessumGold]),
          ),
        ),
      ),
    );
  }
}

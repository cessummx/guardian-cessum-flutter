import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'constants.dart';
import 'error_reporter.dart';
import 'uso_app.dart';
import 'splash_screen.dart';
import 'auth/auth_gate.dart';
import 'theme_controller.dart';
import 'impersonation_banner.dart';

void main() {
  // (ago-8) TODO CORRE DENTRO DE UNA ZONA VIGILADA. Antes, cuando algo
  // tronaba en la app, el error se quedaba en la consola del navegador y
  // nadie se enteraba hasta que un alumno se quejaba. Ahora cada excepción
  // no atendida se registra en el Guardián con la pantalla donde ocurrió.
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    ErrorReporter.iniciar();
    // Cargar preferencias recordadas (tema y tamaño de letra). El origen único
    // de verdad es theme_controller.dart: themeNotifier + textScaleNotifier.
    cargarTema();
    cargarTextScale();
    runApp(const MyApp());
  }, (Object error, StackTrace stack) {
    ErrorReporter.reportar(error, stack);
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final base = ThemeData(
      useMaterial3: true,
      // (9-sep) MONTSERRAT EMPAQUETADA, NO DESCARGADA.
      // Antes el tema la pedía con GoogleFonts.montserratTextTheme, que la
      // baja de los servidores de Google EN TIEMPO DE EJECUCIÓN. Cuando esa
      // descarga no ocurre —red lenta, red restringida, o simplemente que la
      // pantalla se pinta antes de que llegue— el paquete NO avisa: cae a la
      // fuente por omisión y la app se ve con otra letra. Eso era lo que
      // pasaba, y por eso parecía que Montserrat nunca se había aplicado.
      // Ahora los .ttf van dentro de la app (assets/fonts, declarados en
      // pubspec.yaml) y la familia se fija aquí: se ve igual siempre, desde
      // el primer cuadro y sin depender de nadie.
      fontFamily: 'Montserrat',
      scaffoldBackgroundColor: Colors.white,
      colorScheme: ColorScheme.fromSeed(
        seedColor: cessumRed,
        primary: cessumRed,
        secondary: cessumGold,
      ),
      // En Material 3, un ElevatedButton sin color de letra hereda el color
      // "primary" (rojo) como texto. Al pintar el fondo de rojo, la letra
      // quedaba roja sobre rojo (invisible). Fijamos el botón por defecto en
      // rojo con letra blanca: así todos los botones de la app se leen bien.
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: cessumRed,
          foregroundColor: Colors.white,
        ),
      ),
    );

    const darkSurface = Color(0xFF211F1D);
    final dark = ThemeData(
      useMaterial3: true,
      fontFamily: 'Montserrat',
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF161514),
      canvasColor: const Color(0xFF161514),
      cardColor: darkSurface,
      dividerColor: Colors.white24,
      iconTheme: const IconThemeData(color: Colors.white70),
      colorScheme: ColorScheme.fromSeed(
        seedColor: cessumRed,
        brightness: Brightness.dark,
        primary: cessumGold,
        secondary: cessumGold,
      ).copyWith(
        surface: darkSurface,
        onSurface: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: Colors.white70,
        textColor: Colors.white,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: darkSurface,
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: darkSurface,
        contentTextStyle: TextStyle(color: Colors.white),
      ),
      // Superficies sólidas en oscuro (sin el tinte morado de Material 3).
      cardTheme: const CardThemeData(
        color: darkSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 1,
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: darkSurface,
        surfaceTintColor: Colors.transparent,
      ),
      popupMenuTheme: const PopupMenuThemeData(
        color: darkSurface,
        surfaceTintColor: Colors.transparent,
      ),
      // Mismo criterio en modo oscuro: botón por defecto rojo con letra blanca.
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: cessumRed,
          foregroundColor: Colors.white,
        ),
      ),
    );

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, modo, _) {
        return ValueListenableBuilder<double>(
          valueListenable: textScaleNotifier,
          builder: (context, escala, __) {
            return MaterialApp(
              title: 'App CESSUM',
              debugShowCheckedModeBanner: false,
              // El banner de "Ver como..." necesita esta llave para poder
              // sacarte del modo suplantación desde cualquier pantalla.
              navigatorKey: rootNavigatorKey,
              // Anota en qué pantalla va el usuario, para que un error
              // reportado diga DÓNDE ocurrió y no solo qué decía.
              // (25-sep) UsoAppObserver mide a qué pantallas entra cada persona.
              navigatorObservers: [ErrorRouteObserver(), UsoAppObserver()],
              locale: const Locale('es', 'MX'),
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: const [
                Locale('es', 'MX'),
                Locale('es'),
                Locale('en'),
              ],
              themeMode: modo,
              // Los temas ya traen la familia; no hay textTheme que sustituir.
              theme: base,
              darkTheme: dark,
              builder: (context, child) {
                final mq = MediaQuery.of(context);
                return MediaQuery(
                  data: mq.copyWith(textScaler: TextScaler.linear(escala)),
                  // Franja permanente mientras un admin ve la app "como"
                  // otra persona: dice de quién es la cuenta y trae "Salir".
                  // Sin esto se podía quedar suplantando sin darse cuenta.
                  child: ImpersonationBanner(
                    child: child ?? const SizedBox.shrink(),
                  ),
                );
              },
              home: const AuthGate(child: SplashScreen()),
            );
          },
        );
      },
    );
  }
}

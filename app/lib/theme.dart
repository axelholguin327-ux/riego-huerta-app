// Tokens de la Guía de Estilo (docs/Guia_de_Estilo.pdf).
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const verde = Color(0xFF2F7D4F);
  static const verdeOscuro = Color(0xFF1F5A37);
  static const verdeClaro = Color(0xFFE3F1E7);
  static const azul = Color(0xFF2F80ED);
  static const azulClaro = Color(0xFFE6F0FD);
  static const rojo = Color(0xFFD64545);
  static const rojoClaro = Color(0xFFFBE9E9);
  static const ambar = Color(0xFFF2994A);
  static const ambarClaro = Color(0xFFFDF0E4);
  static const ambarTexto = Color(0xFFB5621B);
  static const exito = Color(0xFF27AE60);
  static const fondo = Color(0xFFF4F7F2);
  static const superficie = Colors.white;
  static const texto = Color(0xFF1C2B22);
  static const texto2 = Color(0xFF5F6F66);
  static const borde = Color(0xFFDCE5DC);
  static const gris = Color(0xFFEEF2EE);
}

class AppSpace {
  static const s1 = 4.0, s2 = 8.0, s3 = 12.0, s4 = 16.0, s5 = 24.0, s6 = 32.0;
}

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.verde,
      primary: AppColors.verde,
      secondary: AppColors.azul,
      error: AppColors.rojo,
      surface: AppColors.superficie,
    ),
    scaffoldBackgroundColor: AppColors.fondo,
    fontFamily: GoogleFonts.inter().fontFamily,
  );
  final text = base.textTheme.apply(bodyColor: AppColors.texto, displayColor: AppColors.texto);
  final btnShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
  const btnText = TextStyle(fontSize: 15, fontWeight: FontWeight.w600);

  return base.copyWith(
    textTheme: text,
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.verde,
      foregroundColor: Colors.white,
      elevation: 0,
      titleTextStyle: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white),
    ),
    cardTheme: CardThemeData(
      color: AppColors.superficie,
      elevation: 1,
      shadowColor: const Color(0x141C2B22),
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        shape: btnShape,
        textStyle: btnText,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        shape: btnShape,
        textStyle: btnText,
        foregroundColor: AppColors.verde,
        side: const BorderSide(color: AppColors.verde, width: 1.5),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.superficie,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.borde, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.borde, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.verde, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.rojo, width: 1.5),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.superficie,
      indicatorColor: AppColors.verdeClaro,
      height: 64,
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
            fontSize: 11,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? AppColors.verde : AppColors.texto2,
          )),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.texto,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    sliderTheme: const SliderThemeData(activeTrackColor: AppColors.verde, thumbColor: AppColors.verde),
  );
}

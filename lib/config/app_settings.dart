import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings extends ChangeNotifier {
  double uiScale = 1.0; // Escala de textos e botões (0.9 a 1.4)
  double mapIconScale = 1.0; // Escala dos ícones do mapa (0.8 a 1.6)
  bool mostrarNumeroNoOnibus = false; // false = ícone 🚌, true = número (101)
  bool satelite = false; // false = Ruas, true = Satélite
  String lang = 'pt'; // 'pt', 'es', 'en'
  String modoDaltonismo = 'normal'; // 'normal', 'deuteranopia', 'protanopia', 'tritanopia'

  Future<void> carregar() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      uiScale = (prefs.getDouble('cfg_ui_scale') ?? 1.0).clamp(0.9, 1.4);
      mapIconScale = (prefs.getDouble('cfg_icon_scale') ?? 1.0).clamp(0.8, 1.6);
      mostrarNumeroNoOnibus = prefs.getBool('cfg_bus_num') ?? false;
      satelite = prefs.getBool('cfg_satelite') ?? false;
      lang = prefs.getString('cfg_lang') ?? 'pt';
      modoDaltonismo = prefs.getString('cfg_daltonismo') ?? 'normal';
      notifyListeners();
    } catch (_) {}
  }

  Future<void> setUiScale(double v) async {
    uiScale = v.clamp(0.9, 1.4);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('cfg_ui_scale', uiScale);
  }

  Future<void> setMapIconScale(double v) async {
    mapIconScale = v.clamp(0.8, 1.6);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('cfg_icon_scale', mapIconScale);
  }

  Future<void> setMostrarNumeroNoOnibus(bool v) async {
    mostrarNumeroNoOnibus = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('cfg_bus_num', v);
  }

  Future<void> setSatelite(bool v) async {
    satelite = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('cfg_satelite', v);
  }

  Future<void> setLang(String v) async {
    lang = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cfg_lang', v);
  }

  Future<void> setModoDaltonismo(String v) async {
    modoDaltonismo = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cfg_daltonismo', v);
  }
}

final AppSettings appSettings = AppSettings();
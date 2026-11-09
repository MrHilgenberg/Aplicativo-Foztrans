import 'package:flutter/material.dart';
import '../config/app_config.dart';
import '../config/app_settings.dart';

class _ModoCorItem {
  final String id;
  final String titulo;
  final List<Color> cores;
  const _ModoCorItem(this.id, this.titulo, this.cores);
}

class _IdiomaItem {
  final String codigo;
  final String rotulo;
  const _IdiomaItem(this.codigo, this.rotulo);
}

class ConfiguracoesScreen extends StatelessWidget {
  final VoidCallback onChanged;
  const ConfiguracoesScreen({super.key, required this.onChanged});

  static const Map<String, Map<String, String>> _txt = {
    'pt': {
      'title': 'Configurações e Acessibilidade',
      'sec_map': 'MAPA E EXIBIÇÃO DOS ÔNIBUS',
      'map_type': 'Estilo do mapa',
      'map_streets': 'Mapa de Ruas',
      'map_sat': 'Imagens de Satélite',
      'bus_style': 'Ícone dos ônibus ao vivo',
      'bus_ic': 'Símbolo do ônibus',
      'bus_num': 'Número da linha (ex: 101)',
      'icon_size': 'Tamanho dos ônibus e paradas no mapa',
      'sec_acc': 'ACESSIBILIDADE E LEITURA',
      'text_size': 'Tamanho das letras e botões',
      'colorblind': 'Modo de cores (Daltonismo)',
      'cb_normal': 'Padrão (Cores originais)',
      'cb_deut': 'Deuteranopia (Verde / Vermelho)',
      'cb_prot': 'Protanopia (Vermelho)',
      'cb_trit': 'Tritanopia (Azul / Amarelo)',
      'sec_lang': 'IDIOMA / LANGUAGE',
      'reset': 'Restaurar padrões',
    },
    'es': {
      'title': 'Configuración y Accesibilidad',
      'sec_map': 'MAPA Y VISUALIZACIÓN DE AUTOBUSES',
      'map_type': 'Estilo del mapa',
      'map_streets': 'Mapa de Calles',
      'map_sat': 'Imágenes de Satélite',
      'bus_style': 'Ícono de autobuses en vivo',
      'bus_ic': 'Símbolo de autobús',
      'bus_num': 'Número de línea (ej: 101)',
      'icon_size': 'Tamaño de autobuses y paradas en el mapa',
      'sec_acc': 'ACCESIBILIDAD Y LECTURA',
      'text_size': 'Tamaño de letras y botones',
      'colorblind': 'Modo de color (Daltonismo)',
      'cb_normal': 'Estándar (Colores originales)',
      'cb_deut': 'Deuteranopía (Verde / Rojo)',
      'cb_prot': 'Protanopía (Rojo)',
      'cb_trit': 'Tritanopía (Azul / Amarillo)',
      'sec_lang': 'IDIOMA / LANGUAGE',
      'reset': 'Restaurar valores predeterminados',
    },
    'en': {
      'title': 'Settings & Accessibility',
      'sec_map': 'MAP & LIVE BUS DISPLAY',
      'map_type': 'Map style',
      'map_streets': 'Street Map',
      'map_sat': 'Satellite Imagery',
      'bus_style': 'Live bus marker style',
      'bus_ic': 'Bus icon',
      'bus_num': 'Line number (e.g. 101)',
      'icon_size': 'Bus & stop icon size on map',
      'sec_acc': 'ACCESSIBILITY & TEXT',
      'text_size': 'Text and button size',
      'colorblind': 'Colorblind mode',
      'cb_normal': 'Default (Original colors)',
      'cb_deut': 'Deuteranopia (Red / Green)',
      'cb_prot': 'Protanopia (Red)',
      'cb_trit': 'Tritanopia (Blue / Yellow)',
      'sec_lang': 'LANGUAGE / IDIOMA',
      'reset': 'Reset to defaults',
    },
  };

  String _t(String k) =>
      _txt[appSettings.lang]?[k] ?? _txt['pt']![k] ?? k;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appSettings,
      builder: (context, _) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final cardColor = isDark ? AppConfig.panelDark : AppConfig.panelLight;
        final pctIcone =
            (appSettings.mapIconScale * 100).round().toString() + '%';
        final pctTexto =
            (appSettings.uiScale * 100).round().toString() + '%';

        final modosDaltonismo = <_ModoCorItem>[
          _ModoCorItem('normal', _t('cb_normal'), const [
            Color(0xFFD8402F),
            Color(0xFF1C62B9),
            Color(0xFF2A8A4A),
            Color(0xFF7B3FA3),
          ]),
          _ModoCorItem('deuteranopia', _t('cb_deut'), const [
            Color(0xFFD55E00),
            Color(0xFF0072B2),
            Color(0xFF009E73),
            Color(0xFFCC79A7),
          ]),
          _ModoCorItem('protanopia', _t('cb_prot'), const [
            Color(0xFFE69F00),
            Color(0xFF0072B2),
            Color(0xFF56B4E9),
            Color(0xFFCC79A7),
          ]),
          _ModoCorItem('tritanopia', _t('cb_trit'), const [
            Color(0xFFD92120),
            Color(0xFF008080),
            Color(0xFF114477),
            Color(0xFFAA3377),
          ]),
        ];

        const idiomas = <_IdiomaItem>[
          _IdiomaItem('pt', 'Português (PT)'),
          _IdiomaItem('es', 'Español (ES)'),
          _IdiomaItem('en', 'English (EN)'),
        ];

        return Scaffold(
          appBar: AppBar(
            backgroundColor:
                isDark ? AppConfig.brandDark : AppConfig.brandLight,
            foregroundColor: Colors.white,
            title: Text(
              _t('title'),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 1. SEÇÃO MAPA E ÔNIBUS
              _TituloSecao(texto: _t('sec_map')),
              Container(
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_t('map_type'),
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _BotaoOpcao(
                            ativo: !appSettings.satelite,
                            icone: Icons.map_outlined,
                            rotulo: _t('map_streets'),
                            onTap: () {
                              appSettings.setSatelite(false);
                              onChanged();
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _BotaoOpcao(
                            ativo: appSettings.satelite,
                            icone: Icons.satellite_alt,
                            rotulo: _t('map_sat'),
                            onTap: () {
                              appSettings.setSatelite(true);
                              onChanged();
                            },
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    Text(_t('bus_style'),
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _CardPreviewOnibus(
                            ativo: !appSettings.mostrarNumeroNoOnibus,
                            mostrarNumero: false,
                            rotulo: _t('bus_ic'),
                            onTap: () {
                              appSettings.setMostrarNumeroNoOnibus(false);
                              onChanged();
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _CardPreviewOnibus(
                            ativo: appSettings.mostrarNumeroNoOnibus,
                            mostrarNumero: true,
                            rotulo: _t('bus_num'),
                            onTap: () {
                              appSettings.setMostrarNumeroNoOnibus(true);
                              onChanged();
                            },
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(_t('icon_size'),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 15)),
                        ),
                        Text(
                          pctIcone,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: AppConfig.accentLight,
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      value: appSettings.mapIconScale,
                      min: 0.8,
                      max: 1.6,
                      divisions: 8,
                      activeColor: AppConfig.accentLight,
                      label: pctIcone,
                      onChanged: (v) {
                        appSettings.setMapIconScale(v);
                        onChanged();
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // 2. SEÇÃO ACESSIBILIDADE E DALTONISMO
              _TituloSecao(texto: _t('sec_acc')),
              Container(
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(_t('text_size'),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 15)),
                        ),
                        Text(
                          pctTexto,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: AppConfig.accentLight,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Text('A-',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 15)),
                          onPressed: () {
                            appSettings.setUiScale(appSettings.uiScale - 0.1);
                            onChanged();
                          },
                        ),
                        Expanded(
                          child: Slider(
                            value: appSettings.uiScale,
                            min: 0.9,
                            max: 1.4,
                            divisions: 5,
                            activeColor: AppConfig.accentLight,
                            label: pctTexto,
                            onChanged: (v) {
                              appSettings.setUiScale(v);
                              onChanged();
                            },
                          ),
                        ),
                        IconButton(
                          icon: const Text('A+',
                              style: TextStyle(
                                  fontWeight: FontWeight.w900, fontSize: 17)),
                          onPressed: () {
                            appSettings.setUiScale(appSettings.uiScale + 0.1);
                            onChanged();
                          },
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                    Text(_t('colorblind'),
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15)),
                    const SizedBox(height: 8),
                    for (final m in modosDaltonismo)
                      RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        value: m.id,
                        groupValue: appSettings.modoDaltonismo,
                        activeColor: AppConfig.accentLight,
                        title: Text(m.titulo,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                        secondary: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: m.cores
                              .map((c) => Container(
                                    width: 14,
                                    height: 14,
                                    margin: const EdgeInsets.only(left: 4),
                                    decoration: BoxDecoration(
                                      color: c,
                                      shape: BoxShape.circle,
                                    ),
                                  ))
                              .toList(),
                        ),
                        onChanged: (val) {
                          if (val != null) {
                            appSettings.setModoDaltonismo(val);
                            onChanged();
                          }
                        },
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // 3. SEÇÃO IDIOMA
              _TituloSecao(texto: _t('sec_lang')),
              Container(
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    for (final l in idiomas)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: _BotaoOpcao(
                            ativo: appSettings.lang == l.codigo,
                            icone: Icons.language,
                            rotulo: l.rotulo,
                            onTap: () {
                              appSettings.setLang(l.codigo);
                              onChanged();
                            },
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 24),
              Center(
                child: TextButton.icon(
                  icon: const Icon(Icons.restore),
                  label: Text(_t('reset')),
                  onPressed: () {
                    appSettings.setUiScale(1.0);
                    appSettings.setMapIconScale(1.0);
                    appSettings.setMostrarNumeroNoOnibus(false);
                    appSettings.setSatelite(false);
                    appSettings.setModoDaltonismo('normal');
                    appSettings.setLang('pt');
                    onChanged();
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TituloSecao extends StatelessWidget {
  final String texto;
  const _TituloSecao({required this.texto});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        texto,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
          color: Colors.grey,
        ),
      ),
    );
  }
}

class _BotaoOpcao extends StatelessWidget {
  final bool ativo;
  final IconData icone;
  final String rotulo;
  final VoidCallback onTap;

  const _BotaoOpcao({
    required this.ativo,
    required this.icone,
    required this.rotulo,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: ativo
              ? AppConfig.brandLight
              : Colors.grey.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: ativo ? AppConfig.accentLight : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Icon(icone,
                color: ativo ? Colors.white : Colors.grey, size: 20),
            const SizedBox(height: 6),
            Text(
              rotulo,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: ativo ? Colors.white : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardPreviewOnibus extends StatelessWidget {
  final bool ativo;
  final bool mostrarNumero;
  final String rotulo;
  final VoidCallback onTap;

  const _CardPreviewOnibus({
    required this.ativo,
    required this.mostrarNumero,
    required this.rotulo,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: ativo
              ? AppConfig.brandLight.withOpacity(0.12)
              : Colors.grey.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: ativo ? AppConfig.accentLight : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Container(
              height: 36,
              constraints: BoxConstraints(minWidth: mostrarNumero ? 48 : 36),
              padding: EdgeInsets.symmetric(horizontal: mostrarNumero ? 8 : 0),
              decoration: BoxDecoration(
                color: const Color(0xFF1C62B9),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white, width: 2.5),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 4)
                ],
              ),
              alignment: Alignment.center,
              child: mostrarNumero
                  ? const Text(
                      '101',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 13.5,
                      ),
                    )
                  : const Icon(Icons.directions_bus,
                      color: Colors.white, size: 19),
            ),
            const SizedBox(height: 8),
            Text(
              rotulo,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
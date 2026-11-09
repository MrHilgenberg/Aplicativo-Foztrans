import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ModoDaltonismo {
  nenhum,
  protanopia, // Dificuldade com vermelho
  deuteranopia, // Dificuldade com verde
  tritanopia, // Dificuldade com azul/amarelo
}

class AppSettings {
  final double uiScale;
  final double mapIconScale;
  final bool mostrarNumeroNoOnibus;
  final bool satelite;
  final String idioma;
  final ThemeMode themeMode;
  final ModoDaltonismo daltonismo;

  const AppSettings({
    this.uiScale = 1.0,
    this.mapIconScale = 1.0,
    this.mostrarNumeroNoOnibus = false,
    this.satelite = false,
    this.idioma = 'pt',
    this.themeMode = ThemeMode.system,
    this.daltonismo = ModoDaltonismo.nenhum,
  });

  AppSettings copyWith({
    double? uiScale,
    double? mapIconScale,
    bool? mostrarNumeroNoOnibus,
    bool? satelite,
    String? idioma,
    ThemeMode? themeMode,
    ModoDaltonismo? daltonismo,
  }) {
    return AppSettings(
      uiScale: uiScale ?? this.uiScale,
      mapIconScale: mapIconScale ?? this.mapIconScale,
      mostrarNumeroNoOnibus:
          mostrarNumeroNoOnibus ?? this.mostrarNumeroNoOnibus,
      satelite: satelite ?? this.satelite,
      idioma: idioma ?? this.idioma,
      themeMode: themeMode ?? this.themeMode,
      daltonismo: daltonismo ?? this.daltonismo,
    );
  }
}

final ValueNotifier<AppSettings> appSettingsNotifier =
    ValueNotifier<AppSettings>(const AppSettings());

Future<void> carregarConfiguracoesSalvas() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final uiScale = (prefs.getDouble('cfg_ui_scale') ?? 1.0).clamp(0.85, 1.40);
    final mapIconScale =
        (prefs.getDouble('cfg_map_icon_scale') ?? 1.0).clamp(0.75, 1.50);
    final mostrarNum = prefs.getBool('cfg_bus_num') ?? false;
    final sat = prefs.getBool('cfg_satelite') ?? false;
    final lang = prefs.getString('cfg_idioma') ?? 'pt';
    final temaIdx = prefs.getInt('cfg_tema') ?? 0;
    final daltIdx = prefs.getInt('cfg_daltonismo') ?? 0;

    appSettingsNotifier.value = AppSettings(
      uiScale: uiScale,
      mapIconScale: mapIconScale,
      mostrarNumeroNoOnibus: mostrarNum,
      satelite: sat,
      idioma: ['pt', 'es', 'en'].contains(lang) ? lang : 'pt',
      themeMode:
          ThemeMode.values[temaIdx.clamp(0, ThemeMode.values.length - 1)],
      daltonismo: ModoDaltonismo
          .values[daltIdx.clamp(0, ModoDaltonismo.values.length - 1)],
    );
  } catch (_) {}
}

Future<void> atualizarConfiguracoes(AppSettings novas) async {
  appSettingsNotifier.value = novas;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('cfg_ui_scale', novas.uiScale);
    await prefs.setDouble('cfg_map_icon_scale', novas.mapIconScale);
    await prefs.setBool('cfg_bus_num', novas.mostrarNumeroNoOnibus);
    await prefs.setBool('cfg_satelite', novas.satelite);
    await prefs.setString('cfg_idioma', novas.idioma);
    await prefs.setInt('cfg_tema', novas.themeMode.index);
    await prefs.setInt('cfg_daltonismo', novas.daltonismo.index);
  } catch (_) {}
}

class AppConfig {
  static const String dadosUrl =
      'https://script.google.com/macros/s/AKfycbwaKZCwAvcOlfRuXW_0pEDw4sSIrfqhazUirjPGo1RxGXNFVXj2-bBmAr2S9ACI2Di1/exec';
  static const String rtUrl =
      'https://onibus-foz.alexandre-foztrans.workers.dev/';

  static const List<double> ttuCoords = [-25.5326, -54.5875];
  static const double raioTermPadrao = 130.0;
  static const double velKmh = 18.0;

  // Cores da Marca FOZTRANS
  static const Color brandLight = Color(0xFF12325B);
  static const Color brandDark = Color(0xFF0C2340);
  static const Color accentLight = Color(0xFFF07800);
  static const Color accentDark = Color(0xFFFF9A3D);
  static const Color bgLight = Color(0xFFE9F1F9);
  static const Color bgDark = Color(0xFF0F161C);
  static const Color panelLight = Color(0xFFFFFFFF);
  static const Color panelDark = Color(0xFF17212A);
  static const Color inkLight = Color(0xFF14212B);
  static const Color inkDark = Color(0xFFE8EEF2);
  static const Color mutedLight = Color(0xFF566777);
  static const Color mutedDark = Color(0xFF93A3B0);
  static const Color lineLight = Color(0xFFD5E0EA);
  static const Color lineDark = Color(0xFF2A3742);
  static const Color chipLight = Color(0xFFEEF4FA);
  static const Color chipDark = Color(0xFF1F2B35);

  // Paleta padrão das famílias de linhas (10-70, 101-120, 200-250, 310-380)
  static const Map<String, String> familiaCoresHex = {
    'f0': '#d8402f',
    'f1': '#1c62b9',
    'f2': '#2a8a4a',
    'f3': '#7b3fa3',
    'fe': '#b07a12',
  };

  // Paletas adaptadas para Daltonismo (Alto Contraste Okabe-Ito / Tol)
  static Map<String, String> coresPorModoDaltonismo(ModoDaltonismo modo) {
    switch (modo) {
      case ModoDaltonismo.protanopia:
        return const {
          'f0': '#D55E00', // Âmbar forte (substitui vermelho escuro)
          'f1': '#0072B2', // Azul Royal
          'f2': '#009E73', // Turquesa / Ciano-verde
          'f3': '#CC79A7', // Magenta / Violeta claro
          'fe': '#E69F00', // Ouro
        };
      case ModoDaltonismo.deuteranopia:
        return const {
          'f0': '#E66100', // Laranja queimado vivo
          'f1': '#005AB5', // Azul cobalto
          'f2': '#40B0A6', // Verde-água / Teal
          'f3': '#5D3A9B', // Roxo profundo
          'fe': '#D4A017', // Mostarda
        };
      case ModoDaltonismo.tritanopia:
        return const {
          'f0': '#D92B2B', // Carmim intenso
          'f1': '#008080', // Ciano escuro (substitui azul)
          'f2': '#1B7837', // Verde floresta
          'f3': '#993366', // Ameixa / Vinho
          'fe': '#B85D00', // Bronze
        };
      case ModoDaltonismo.nenhum:
        return familiaCoresHex;
    }
  }

  static const Map<String, List<String>> grupos = {
    '101': ['101', '102'],
  };

  static final Map<String, Map<String, dynamic>> linhasCfg = {
    "10": {
      "var": {
        "CIDADE NOVA>>CENTRO2": "",
        "CIDADE NOVA >> CENTRO": "",
        "CIDADE NOVA-5MIN>>CENTRO": "",
        "CENTRO-DI>>CIDADE NOVA-DI": "Direto",
        "CIDADE NOVA-5MIN-DI>>CENTRO": "Direto",
        "CENTRO-DI >> CIDADE NOVA-AL-DI": "Direto · Almada",
        "CIDADE NOVA>AL>CENTRO": "Direto · Almada",
        "CENTRO-AL-DI- CAMP UNI>>CIDADE NOVA": "Direto · Almada · Unioeste",
        "CIDADE NOVA-AL-DI-CAMP UNI>>CENTRO": "Direto · Almada · Unioeste",
        "CENTRO-AL-CAMP UNI>>CIDADE NOVA": "Almada · Unioeste",
        "CIDADE NOVA-5MIN-DI>>TTU": "Direto · só até o TTU",
        "CIDADE NOVA-5MIN>>TTU": "só até o TTU",
        "MAC>>CIDADE NOVA": "McDonald’s",
        "MAC-DI>>CIDADE NOVA": "McDonald’s · Direto",
        "MAC-DI-AL>>CIDADE NOVA": "McDonald’s · Direto · Almada",
        "CENTRO-DI >> REC. AL": "Direto · só até o Almada",
        "CENTRO>>AL": "só até o Almada"
      },
      "ala": "1"
    },
    "40": {
      "var": {
        "VILA C-DI>>TTU": "",
        "VILA C-5MIN-DI>>TTU": "",
        "VILA C>>TTU": "passa na Unioeste",
        "VILA C-CMP UNI>>TTU":
            "entra no campus da Unioeste (sáb.: só até a entrada)"
      },
      "ala": "3"
    },
    "45": {
      "var": {"Rodoviária - RODOVIÁRIA>>TTU": ""},
      "ala": "3"
    },
    "50": {
      "var": {
        "VILA A VIA PARANÁ": "",
        "VILA A VIA PARANÁ-DI": "direto pela Av. República Argentina",
        "VILA A VIA PARANÁ-COL.A.S": "até o Colégio Ayrton Senna (seg. a sex.)",
        "VILA A VIA PARANÁ-JD APORÃ": "via Jd. Aporã"
      },
      "ala": "2"
    },
    "55": {
      "var": {
        "VILA A VIA JK": "",
        "SOLTURA VILA A VIA JK": "",
        "VILA A VIA JK-CER IV": "via Travessa Florai",
        "VILA A VIA JK-CER IV-COL.A.S":
            "via Travessa Florai e Colégio Ayrton Senna",
        "VILA A VIA JK-JD.CURITIBANO": "via Jd. Curitibano",
        "RECOLHIMENTO ZIZO": "só até a Escola Zizo"
      },
      "ala": "1"
    },
    "65": {
      "var": {
        "UNIVERSITÁRIA": "",
        "UNIVERSITÁRIA-5MIN": "",
        "UNIVERSITÁRIA-CMP UNI": "entra no campus da Unioeste",
        "UNIVERSITÁRIA-ITAIPU PARQUETEC":
            "via Itaipu Parquetec (não passa no Hospital Costa Cavalcanti)"
      },
      "ala": "1"
    },
    "70": {
      "var": {
        "CIDADE NOVA - INSS-DI": "",
        "CIDADE NOVA - INSS-5MIN-DI": ""
      },
      "ala": "3"
    },
    "101": {
      "var": {
        "[N-DI]Vila C NORTE- DIRETO": "Norte · direto",
        "[S-PTE]VILA C NORTE-S-N": "Sul → Norte · Ponte",
        "[PTE-N]VILA C NORTE-N-S": "Norte → Sul · Ponte",
        "[S-PTE]Vila C Sul - PONTE (102)": "Sul · Ponte",
        "[S-DI]SUL-DIR": "Sul · direto",
        "[N-S-DI]VILA C NORTE-5MIN-N-S-DI": "Norte → Sul · direto",
        "[DI-S-GL-N]DI-S-GL": "Sul → Grande Lago → Norte · direto",
        "[PTE-N]NORTE-PONTE (102)": "Norte · Ponte",
        "[S-N-PTE]PRIMEIRA V-S-N (102)": "Sul → Norte · Ponte",
        "[N-S] primeira viagem ponte N-S": "Norte → Sul · Ponte",
        "[N-S-PTE-CTRO]N-S-PONTE VIA CTO": "Norte → Sul · Ponte e Centro",
        "[S-GL-N-PTE]PRIMEIRA V-S-GL-N (102)":
            "Sul → Grande Lago → Norte · Ponte",
        "[S-GL-N-DI]PRIM-S-GL-N-DIRT (102)":
            "Sul → Grande Lago → Norte · direto",
        "[S-N-DI-CENTRO]S-N-DIRETO VIA CTO": "Sul → Norte · direto, via Centro",
        "[N-S-DI-CETRO]N-S-DIRETO VIA CTO": "Norte → Sul · direto, via Centro",
        "S-CMP UNI-PTE": "Sul · Unioeste e Ponte",
        "[S-N-CMP UNI-DI]SUL - NORTE - CMP UNI - DI":
            "Sul → Norte · direto, via Unioeste",
        "SUL-CMP UNI-DI": "Sul · direto, via Unioeste",
        "VILA C NORTE-5MIN-S-GL-N-DI":
            "Sul → Grande Lago → Norte · direto",
        "VILA C NORTE-F-5MIN-S-N-DI": "Sul → Norte · direto",
        "[TTU-PTE-S-N]Mac-SUL-NORTE (102)": "McDonald’s · Sul → Norte · Ponte",
        "[DI-S]VILA C S - DIREITO - REC (102)": "Sul · direto",
        "REC - TTU - N - S": "Norte → Sul · direto",
        "[TTU-DI-N-S]MAC-N-S-DIRETO (102)": "McDonald’s · Norte → Sul · direto",
        "[TTU-DI-CMP-UNI-S-N]MAC-DI-CMP UNI-S-N":
            "McDonald’s · Sul → Norte · direto, via Unioeste",
        "[PTE-S]VILA C Sul-PONTE - REC (102)": "Sul · Ponte",
        "[PONTE]TTU -> PONTE": "só até a Ponte",
        "Vila C Sul -PONTE": "Sul · Ponte",
        "NORTE-PONTE": "Norte · Ponte",
        "PRIMEIRA V-S-N": "Sul → Norte · Ponte",
        "NORTE-DIRETO": "Norte · direto",
        "SUL-DIR-GL": "Sul → Grande Lago · direto"
      },
      "nome": "Vila C Norte e Sul",
      "ala": "1"
    },
    "103": {
      "var": {
        "PTE": "Ponte",
        "PONTE": "Ponte",
        "PTE - JD PR": "Ponte - Jd. Paraná",
        "JD PR - DI": "Jd. Paraná - Direto",
        "PRIM-JD PR DI": "Jd. Paraná - Direto",
        "PRIM-JD PR-PTE": "Ponte - Jd. Paraná",
        "T.B-PTE": "Ponte - Templo Budista",
        "DI": "direto"
      },
      "ala": "1"
    },
    "105": {
      "var": {
        "Via GM": "via Av. General Meira",
        "ULTIMA VIAGEM -Via GM": "via Av. General Meira",
        "Via VY": "via Vila Yolanda",
        "PRIMEIRA VIAGEM": "",
        "Novo Horizonte - rodoviária": "até a Rodoviária",
        "Rodoviaria GM": "sai da Rodoviária · via Av. General Meira"
      },
      "ala": "2"
    },
    "110": {
      "var": {
        "M3 - M3-DI-GEN-MEIRA": "direto pela Av. General Meira (sem o Sohab)",
        "M3 - PRIMEIRA V-PROF-II": "via Profilurb II",
        "M3 - PROF-II": "via Profilurb II",
        "M3 - Sohab m3": "via Sohab",
        "M3 - AG.Marinha-M3": "via R. Água Marinha",
        "M3 - Roda Gigante": "via Roda Gigante (R. Quixadá)"
      },
      "ala": "2"
    },
    "116": {
      "var": {
        "Jd das Flores": "via Jd. das Flores",
        "PRIM-JD FLORES": "via Jd. das Flores",
        "JD Polonia": "via Jd. Polônia",
        "JD Guaira": "via Jd. Guaíra",
        "PRIM-JD Polonia-JD Guaira": "via Jd. Polônia e Jd. Guaíra",
        "via JF-via JG": "via Jd. das Flores e Jd. Guaíra"
      },
      "ala": "2"
    },
    "117": {
      "var": {
        "Sohab-Proflurb": "via Sohab e Profilurb II",
        "PROF.II.-SOHAB": "via Profilurb II e Sohab",
        "PROF.II.-SOHAB RC": "via Profilurb II e Sohab",
        "Profilurb-II": "só Profilurb II",
        "SOHAB": "só Sohab",
        "M3-SOHAB": "via Marco das Três Fronteiras e Sohab",
        "PROF.II-M3": "via Profilurb II e Marco das Três Fronteiras",
        "SOHAB-M3-PROF.II": "via Sohab, Marco e Profilurb II"
      },
      "ala": "2"
    },
    "120": {
      "var": {
        "Parque Nacional": "",
        "Parque Nacional - CRV FECHADO": "não entra no Centro de Visitantes"
      },
      "nome": "Parque Nacional",
      "ala": "2"
    },
    "200": {
      "var": {
        "Gleba Guarani - CEDRO": "",
        "PRIM-CEDRO": "",
        "Gleba Guarani-CEDRO REC": "",
        "PRIM-CEDRO-INSS": "via INSS (Av. Paraná)",
        "Via Cedro - INSS": "via INSS (Av. Paraná)",
        "PRIM-CEDRO-INSS ATÉ O CENTRO": "via INSS · vai até o Centro",
        "VIA CEDRO - UPA": "via UPA",
        "VIA A.BUSSATO": "via Colégio Arnaldo Busatto",
        "Via ponte": "só até a Ponte"
      },
      "ala": "3"
    },
    "205": {
      "var": {
        "Santa Rita": "",
        "primeira viagem": "",
        "Direto": "direto (sem o Lagoa Dourada)",
        "PONTE- VIA ARNALDO BUSATTO":
            "via Colégio Arnaldo Busatto (seg. a sex.)",
        "VIA PRAÇA": "via Praça Três Lagoas"
      }
    },
    "210": {
      "var": {
        "TTU >> PQ. Imperatriz": "",
        "VIA CAPS": "via CAPS (R. Portugal)",
        "PRIMEIRA V-SEST SENAT": "sai do SEST/SENAT"
      },
      "ala": "3"
    },
    "225": {
      "var": {
        "Centro - Três Lagoas Centro": "",
        "Centro - COL - PDO": "via Colombelli e Porto Dourado",
        "Centro - COL - PDO - PQ DA LAGOA":
            "via Colombelli, Porto Dourado e Pq. da Lagoa",
        "Centro - JD. ATLANTIS - VIA INSS": "via Jd. Atlantis e INSS",
        "Centro - Volta ABV - Sol de Maio":
            "via Alto da Boa Vista e Sol de Maio",
        "Centro - SOL DE MAIO - ABV": "via Sol de Maio e Alto da Boa Vista",
        "Centro - ABV - TERMINAL": "via Alto da Boa Vista",
        "Centro - COL-INSS": "via Colombelli e INSS",
        "Centro - Jd Alvorada": "via Jd. Alvorada",
        "Centro - EXP INSS": "via Av. Nacional",
        "Centro - TTU - PRAÇA TRÊS LAGOAS": "até a Praça Três Lagoas",
        "Centro - Três Lagoas - DI": "direto, sem passar pelo Centro",
        "Centro - INSS-UPA-COL": "via INSS, UPA e Colombelli",
        "Centro - JD.ATL.JD.ALV.COL-PDO":
            "via Jd. Atlantis, Jd. Alvorada, Colombelli e Porto Dourado"
      },
      "ala": "3"
    },
    "225A": {
      "var": {
        "ATLANTIS -PRAÇA": "Res. Atlantis",
        "RES. ATLANTIS - VIA UBS": "Res. Atlantis, via UBS São João",
        "ABV - PRAÇA": "Alto da Boa Vista",
        "ANGATUBA - PQ. DA LAGOA - PDO":
            "Angatuba, Pq. da Lagoa e Porto Dourado",
        "PQ.LAG - BOICY - COL": "Pq. da Lagoa, Boicy e Colombelli",
        "ANGATUBA - CEDRO": "Angatuba e Jd. Cedro",
        "COLO - ANG - CEDRO -PQ. LAG - PDO":
            "Colombelli, Angatuba, Cedro, Pq. da Lagoa e Porto Dourado",
        "AG-CEDRO-PQ. LAG-PDO":
            "Angatuba, Cedro, Pq. da Lagoa e Porto Dourado"
      }
    },
    "230": {
      "var": {
        "Ponte - Três Lagoas - Ponte": "",
        "Ponte - Três Lagoas (Ponte) Rec": "",
        "Ponte - DI-MARAN": "direto pela Av. João Ricieri Maran"
      }
    },
    "245": {
      "var": {
        "Praia - INSS-UPA-COL": "",
        "Praia - INSS-UPA-COL T10": "",
        "Praia - PDO-COL-UPA-INSS": "via Porto Dourado",
        "Praia - INSS-UPA-COL - OLIVEIRAS": "via Jd. Oliveiras",
        "Praia - JD.COL-JD.OLIVEIRAS-INSS-UPA": "via Jd. Oliveiras",
        "Praia - PQ. LAG - INSS-UPA-COL -": "via Pq. da Lagoa",
        "Praia - COL": "sem INSS e UPA",
        "Praia - EXP INSS": "via Av. Nacional",
        "Praia - COL-PDO": "via Porto Dourado, sem INSS e UPA",
        "Praia - PQ DA LAGOA - COL.": "via Pq. da Lagoa, sem INSS e UPA",
        "Praia - PQ DA LAGOA - COLO - OLIVEIRAS - INSS":
            "via Pq. da Lagoa e Jd. Oliveiras",
        "Praia - JD. ATLANTIS - VIA INSS": "via Jd. Atlantis",
        "Praia - PDO-COL-Oliveiras-UPA-INSS":
            "via Porto Dourado e Jd. Oliveiras",
        "Praia - COL-PDO-Oliveiras":
            "via Porto Dourado e Jd. Oliveiras, sem INSS e UPA",
        "Praia - PDO - COL": "via Porto Dourado, sem INSS e UPA",
        "Praia - COL - PDO - JD ATL": "via Porto Dourado e Jd. Atlantis",
        "Praia - INSS-UPA-COL-SATURNINO": "via R. Saturnino",
        "Praia - INSS-UPA-COL-ARAUCARIA": "via Araucária",
        "Praia - INSS-UPA-COL - JD. ATLANTIS - ULTIMA VIAGEM":
            "via Jd. Atlantis"
      },
      "ala": "3"
    },
    "250": {
      "var": {
        "Três Bandeiras": "",
        "IV - CND": "via Curitibano IV e Jd. Canadá",
        "Via CTO": "desce ao Centro",
        "CTO-INSS-P.P.-I-II-CND-IV":
            "via Centro, INSS, Pq. Presidente I e II, Jd. Canadá e Curitibano IV",
        "INSS - P.P II": "via INSS e Pq. Presidente II",
        "INSS - PP1-2 - CND.IV":
            "via INSS, Pq. Presidente I e II, Jd. Canadá e Curitibano IV"
      },
      "ala": "3"
    },
    "310": {
      "var": {
        "LIBRA II": "",
        "PRIMEIRA VIAJEM LIBRA II-CTO": "desce ao Centro",
        "LIBRA II-CTO-TTU-REC": "desce ao Centro",
        "LIBRA II-AV. JULES RIMET": "via Av. Jules Rimet"
      },
      "ala": "3"
    },
    "315": {
      "var": {
        "Primeiro de maio": "",
        "VIA-LGTR": "via Lote Grande",
        "PORTAL-CTO-T6": "desce ao Centro",
        "PORTAL-CTO": "desce ao Centro",
        "PORTAL-CTO-REC": "desce ao Centro"
      },
      "ala": "3"
    },
    "320": {
      "var": {
        "INTERBAIRROS -UNI": "",
        "PRIMEIRA VIAJEM": "",
        "TRES-UNI-VILA C": "",
        "UNI-RENDIÇÃO PARTE(1)": "",
        "UNI-RENDIÇÃO PARTE(2)": "",
        "ULTIMA VIAJEM- UNI": "",
        "INTERBAIRROS *": "sem passar na Unioeste",
        "PRIM-VIJ *": "sem passar na Unioeste",
        "INTEBAIRROS*-RENDIÇÃO PARTE(1)": "sem passar na Unioeste",
        "INTERBAIRROS*- RENDIÇAO PARTE(2)": "sem passar na Unioeste",
        "ULTIMA VIAJEM *": "sem passar na Unioeste",
        "INTERBAIRROS - CAMPUS UNIOESTE": "entra no campus da Unioeste"
      }
    },
    "325": {
      "var": {
        "NAIPI": "via Jd. Naipi",
        "NAIPI - VF": "via Jd. Naipi e Vila Florata",
        "MARACANÃ - VF": "via Maracanã e Vila Florata",
        "JD. Guarapuava": "via Maracanã"
      },
      "ala": "3"
    },
    "335": {
      "var": {
        "Morumbi-DI": "",
        "Morumbi Até o centro": "vai até o Centro",
        "Morumbi - Via Centro": "via Centro",
        "Rodoviária": "sai da Rodoviária",
        "Gaúcha": "sai da Av. JK (Loja Gaúcha)"
      },
      "ala": "3"
    },
    "345": {
      "var": {
        "TTU-UNIMED": "",
        "VIA APARECIDINHA": "via Aparecidinha"
      },
      "ala": "2"
    },
    "350": {
      "var": {
        "Linha 350": "",
        "Linha 0350 ( Rec)": "",
        "DI": "direto",
        "Linha 0350( Rec) Direto": "direto",
        "DI-BARÃO": "direto · até o Colégio Barão",
        "PONTE-BARÃO": "via Colégio Barão"
      }
    },
    "360": {
      "var": {"PORTAL": "", "PORTAL-REC": ""},
      "ala": "1"
    },
    "380": {
      "var": {
        "JD. São Roque": "",
        "Via Av. das Cataratas": "via Av. das Cataratas"
      },
      "ala": "2"
    }
  };
}
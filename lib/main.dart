import 'package:flutter/material.dart';
import 'config/app_config.dart';
import 'config/app_settings.dart';
import 'models/transporte_models.dart';
import 'screens/home_screen.dart';
import 'services/api_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await appSettings.carregar();
  runApp(const MobiFozApp());
}

class MobiFozApp extends StatelessWidget {
  const MobiFozApp({super.key});

  /// Retorna a matriz óptica de correção de cores para aplicar sobre a tela inteira
  ColorFilter _obterFiltroDaltonismo(String modo) {
    switch (modo) {
      case 'deuteranopia':
        // Filtro para Deuteranopia (ajuda a diferenciar Verde / Vermelho)
        return const ColorFilter.matrix(<double>[
          0.625, 0.375, 0.0,   0, 0,
          0.700, 0.300, 0.0,   0, 0,
          0.0,   0.300, 0.700, 0, 0,
          0,     0,     0,     1, 0,
        ]);
      case 'protanopia':
        // Filtro para Protanopia (compensa a perda de sensibilidade ao Vermelho)
        return const ColorFilter.matrix(<double>[
          0.567, 0.433, 0.0,   0, 0,
          0.558, 0.442, 0.0,   0, 0,
          0.0,   0.242, 0.758, 0, 0,
          0,     0,     0,     1, 0,
        ]);
      case 'tritanopia':
        // Filtro para Tritanopia (compensa confusão entre Azul / Amarelo)
        return const ColorFilter.matrix(<double>[
          0.950, 0.050, 0.0,   0, 0,
          0.0,   0.433, 0.567, 0, 0,
          0.0,   0.475, 0.525, 0, 0,
          0,     0,     0,     1, 0,
        ]);
      default:
        // Matriz identidade (cores originais sem alteração)
        return const ColorFilter.matrix(<double>[
          1, 0, 0, 0, 0,
          0, 1, 0, 0, 0,
          0, 0, 1, 0, 0,
          0, 0, 0, 1, 0,
        ]);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appSettings,
      builder: (context, _) {
        final modoCor = appSettings.modoDaltonismo;
        return MaterialApp(
          title: 'FozBus · FOZTRANS',
          debugShowCheckedModeBanner: false,
          themeMode: ThemeMode.system,
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            scaffoldBackgroundColor: AppConfig.bgLight,
            colorScheme: ColorScheme.fromSeed(
              seedColor: AppConfig.brandLight,
              primary: AppConfig.brandLight,
              secondary: AppConfig.accentLight,
              brightness: Brightness.light,
            ),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            scaffoldBackgroundColor: AppConfig.bgDark,
            colorScheme: ColorScheme.fromSeed(
              seedColor: AppConfig.brandDark,
              primary: AppConfig.brandDark,
              secondary: AppConfig.accentDark,
              brightness: Brightness.dark,
            ),
          ),
          builder: (context, child) {
            final mq = MediaQuery.of(context);
            Widget tela = MediaQuery(
              data: mq.copyWith(
                  textScaler: TextScaler.linear(appSettings.uiScale)),
              child: child!,
            );

            // Se algum modo daltônico estiver ativo, aplica o filtro na tela inteira!
            if (modoCor != 'normal') {
              tela = ColorFiltered(
                colorFilter: _obterFiltroDaltonismo(modoCor),
                child: tela,
              );
            }
            return tela;
          },
          home: const _InicializadorScreen(),
        );
      },
    );
  }
}

class _InicializadorScreen extends StatefulWidget {
  const _InicializadorScreen();

  @override
  State<_InicializadorScreen> createState() => _InicializadorScreenState();
}

class _InicializadorScreenState extends State<_InicializadorScreen> {
  final ApiService _api = ApiService();
  String _mensagem = 'Carregando linhas, pontos e horários da FOZTRANS…';
  bool _erro = false;

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  Future<void> _iniciar() async {
    setState(() {
      _erro = false;
      _mensagem = 'Carregando linhas, pontos e horários da FOZTRANS…';
    });

    DadosTransporteGeral? dados = await _api.carregarCacheLocal();
    dados ??= await _api.baixaDados();

    if (!mounted) return;
    if (dados != null && dados.linhas.isNotEmpty) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => HomeScreen(dadosIniciais: dados!)),
      );
    } else {
      setState(() {
        _erro = true;
        _mensagem =
            'Não foi possível baixar os dados iniciais. Verifique sua conexão com a internet.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConfig.brandLight,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                constraints: const BoxConstraints(maxWidth: 260),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.asset(
                    'assets/fozbus_logo.png',
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      child: Text(
                        'FOZBUS',
                        style: TextStyle(
                          color: AppConfig.brandLight,
                          fontWeight: FontWeight.w900,
                          fontSize: 24,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              if (!_erro)
                const CircularProgressIndicator(color: AppConfig.accentLight),
              const SizedBox(height: 18),
              Text(
                _mensagem,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
              if (_erro) ...[
                const SizedBox(height: 16),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppConfig.accentLight,
                    foregroundColor: const Color(0xFF1A0F00),
                  ),
                  onPressed: _iniciar,
                  child: const Text('Tentar novamente',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
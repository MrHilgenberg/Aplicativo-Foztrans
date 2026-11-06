import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'config/app_config.dart';
import 'models/transporte_models.dart';
import 'screens/home_screen.dart';
import 'services/api_service.dart';


/// Controlador global de escala para acessibilidade (0.9x a 1.4x)
final ValueNotifier<double> appScaleNotifier = ValueNotifier<double>(1.0);

Future<void> alterarEscalaApp(double novaEscala) async {
  final valor = novaEscala.clamp(0.9, 1.4);
  appScaleNotifier.value = valor;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('app_ui_scale', valor);
  } catch (_) {}
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final prefs = await SharedPreferences.getInstance();
    final salvo = prefs.getDouble('app_ui_scale');
    if (salvo != null) {
      appScaleNotifier.value = salvo.clamp(0.9, 1.4);
    }
  } catch (_) {}
  runApp(const MobiFozApp());
}

class MobiFozApp extends StatelessWidget {
  const MobiFozApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: appScaleNotifier,
      builder: (context, scale, _) {
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
            return MediaQuery(
              data: mq.copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            );
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
              // Logo Foztrans.png direto de assets/Foztrans.png com cantos arredondados
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
                    'assets/fozbus_icone.png',
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      child: Text(
                        'FOZTRANS',
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
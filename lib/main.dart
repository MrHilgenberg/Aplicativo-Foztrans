import 'package:flutter/material.dart';
import 'config/app_config.dart';
import 'models/transporte_models.dart';
import 'screens/home_screen.dart';
import 'services/api_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MobiFozApp());
}

class MobiFozApp extends StatelessWidget {
  const MobiFozApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ônibus de Foz do Iguaçu · FOZTRANS',
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
      home: const _InicializadorScreen(),
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

    // 1. Tenta o cache local para abertura instantânea
    DadosTransporteGeral? dados = await _api.carregarCacheLocal();

    // 2. Se não houver cache local ainda, baixa do Google Apps Script
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'FOZTRANS',
                  style: TextStyle(
                    color: AppConfig.brandLight,
                    fontWeight: FontWeight.w900,
                    fontSize: 24,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              const SizedBox(height: 24),
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
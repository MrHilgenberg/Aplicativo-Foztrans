import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../config/app_config.dart';
import '../models/transporte_models.dart';
import '../services/supabase_service.dart';

class _CategoriaInfo {
  final String id;
  final String titulo;
  final String subtitulo;
  final IconData icone;
  final Color cor;
  final bool pedeLinha;
  final bool pedePrefixo;
  final bool pedeHorario;
  final bool pedeLocalOuTela;
  final String labelLocalOuTela;
  final String hintDescricao;

  const _CategoriaInfo({
    required this.id,
    required this.titulo,
    required this.subtitulo,
    required this.icone,
    required this.cor,
    this.pedeLinha = false,
    this.pedePrefixo = false,
    this.pedeHorario = false,
    this.pedeLocalOuTela = false,
    this.labelLocalOuTela = '',
    required this.hintDescricao,
  });
}

class ReclamacaoScreen extends StatefulWidget {
  final List<LinhaOnibus> linhas;
  const ReclamacaoScreen({super.key, required this.linhas});

  @override
  State<ReclamacaoScreen> createState() => _ReclamacaoScreenState();
}

class _ReclamacaoScreenState extends State<ReclamacaoScreen> {
  final SupabaseService _supa = SupabaseService();
  final TextEditingController _prefixoCtrl = TextEditingController();
  final TextEditingController _horarioCtrl = TextEditingController();
  final TextEditingController _localCtrl = TextEditingController();
  final TextEditingController _descCtrl = TextEditingController();

  _CategoriaInfo? _catSelecionada;
  String? _linhaSelecionada;
  Uint8List? _fotoBytes;
  String _fotoNome = '';
  bool _enviando = false;

  static const List<_CategoriaInfo> _categorias = [
    _CategoriaInfo(
      id: 'denuncia',
      titulo: 'Denúncia / Conduta',
      subtitulo:
          'Motorista que não parou no ponto, direção perigosa, superlotação ou desvio de rota.',
      icone: Icons.campaign_rounded,
      cor: Color(0xFFD8402F),
      pedeLinha: true,
      pedePrefixo: true,
      pedeHorario: true,
      pedeLocalOuTela: true,
      labelLocalOuTela: 'Em qual ponto ou rua aconteceu?',
      hintDescricao: 'Descreva o que aconteceu com o máximo de detalhes…',
    ),
    _CategoriaInfo(
      id: 'atraso',
      titulo: 'Atraso ou Falta de Ônibus',
      subtitulo:
          'Ônibus atrasou muito além do previsto ou não realizou a viagem programada.',
      icone: Icons.schedule_rounded,
      cor: Color(0xFFF07800),
      pedeLinha: true,
      pedePrefixo: false,
      pedeHorario: true,
      pedeLocalOuTela: true,
      labelLocalOuTela: 'Em qual ponto você estava aguardando?',
      hintDescricao:
          'Conte qual horário você esperava e quanto tempo ficou no ponto…',
    ),
    _CategoriaInfo(
      id: 'acidente',
      titulo: 'Acidente ou Problema no Ônibus',
      subtitulo:
          'Ônibus quebrado, elevador de cadeirante com defeito, goteira ou acidente de trânsito.',
      icone: Icons.car_crash_rounded,
      cor: Color(0xFFB91C1C),
      pedeLinha: true,
      pedePrefixo: true,
      pedeHorario: true,
      pedeLocalOuTela: true,
      labelLocalOuTela: 'Local aproximado do ocorrido',
      hintDescricao: 'Explique qual foi o defeito ou acidente…',
    ),
    _CategoriaInfo(
      id: 'ponto',
      titulo: 'Problema em Ponto de Ônibus',
      subtitulo:
          'Ponto quebrado, sem cobertura, sem iluminação ou localização errada no mapa.',
      icone: Icons.pin_drop_rounded,
      cor: Color(0xFF1C62B9),
      pedeLinha: false,
      pedePrefixo: false,
      pedeHorario: false,
      pedeLocalOuTela: true,
      labelLocalOuTela: 'Endereço ou ponto de referência da parada',
      hintDescricao:
          'Descreva o problema na estrutura do ponto ou a correção no mapa…',
    ),
    _CategoriaInfo(
      id: 'bug',
      titulo: 'Bug no App ou Sugestão',
      subtitulo:
          'Erro no aplicativo FozBus, horário diferente da tabela oficial ou ideia de melhoria.',
      icone: Icons.bug_report_rounded,
      cor: Color(0xFF2A8A4A),
      pedeLinha: false,
      pedePrefixo: false,
      pedeHorario: false,
      pedeLocalOuTela: true,
      labelLocalOuTela: 'Em qual parte do app ocorreu? (ex: Mapa, Planejador)',
      hintDescricao: 'Conte o que deu errado no app ou qual é a sua sugestão…',
    ),
  ];

  @override
  void dispose() {
    _prefixoCtrl.dispose();
    _horarioCtrl.dispose();
    _localCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _escolherFoto() async {
    try {
      final picker = ImagePicker();
      final xfile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 78,
      );
      if (xfile != null) {
        final bytes = await xfile.readAsBytes();
        setState(() {
          _fotoBytes = bytes;
          _fotoNome = xfile.name;
        });
      }
    } catch (_) {}
  }

  Future<void> _selecionarHorario() async {
    final agora = TimeOfDay.now();
    final escolhido = await showTimePicker(
      context: context,
      initialTime: agora,
    );
    if (escolhido != null) {
      final hh = escolhido.hour.toString().padLeft(2, '0');
      final mm = escolhido.minute.toString().padLeft(2, '0');
      setState(() {
        _horarioCtrl.text = hh + ':' + mm;
      });
    }
  }

  Future<void> _enviar() async {
    final cat = _catSelecionada!;
    if (cat.pedeLinha && (_linhaSelecionada == null || _linhaSelecionada!.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, selecione a linha de ônibus.')),
      );
      return;
    }
    if (_descCtrl.text.trim().length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Por favor, escreva uma descrição do ocorrido.')),
      );
      return;
    }

    setState(() => _enviando = true);
    final ext = _fotoNome.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
    final res = await _supa.enviarReclamacao(
      categoria: cat.id,
      linha: _linhaSelecionada ?? '',
      prefixo: _prefixoCtrl.text,
      horarioOcorrido: _horarioCtrl.text,
      localOuTela: _localCtrl.text,
      descricao: _descCtrl.text,
      fotoBytes: _fotoBytes,
      fotoExt: ext,
    );

    if (!mounted) return;
    setState(() => _enviando = false);

    if (res == 'OK') {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Relato enviado!'),
          content: const Text(
              'Sua mensagem foi registrada e enviada diretamente para a equipe do Foztrans. Obrigado por ajudar a melhorar o transporte de Foz do Iguaçu!'),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Fechar'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? AppConfig.panelDark : AppConfig.panelLight;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: isDark ? AppConfig.brandDark : AppConfig.brandLight,
        foregroundColor: Colors.white,
        leading: _catSelecionada != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _catSelecionada = null),
              )
            : null,
        title: Text(
          _catSelecionada == null
              ? 'Ouvidoria e Suporte FozBus'
              : _catSelecionada!.titulo,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
      ),
      body: _catSelecionada == null
          ? _construirEscolhaCategoria(cardColor, isDark)
          : _construirFormulario(_catSelecionada!, cardColor, isDark),
    );
  }

  Widget _construirEscolhaCategoria(Color cardColor, bool isDark) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'O que você deseja relatar para a equipe do Foztrans?',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
        const SizedBox(height: 6),
        const Text(
          'Escolha uma categoria abaixo para abrirmos os campos certos:',
          style: TextStyle(color: Colors.grey, fontSize: 13.5),
        ),
        const SizedBox(height: 16),
        for (final c in _categorias)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: cardColor,
              borderRadius: BorderRadius.circular(12),
              elevation: 1,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  setState(() {
                    _catSelecionada = c;
                    if (_horarioCtrl.text.isEmpty) {
                      final now = TimeOfDay.now();
                      _horarioCtrl.text =
                          now.hour.toString().padLeft(2, '0') +
                              ':' +
                              now.minute.toString().padLeft(2, '0');
                    }
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: c.cor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(c.icone, color: c.cor, size: 26),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              c.titulo,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15.5,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              c.subtitulo,
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: Colors.grey),
                    ],
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF1E9E4A).withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF1E9E4A)),
          ),
          child: Row(
            children: [
              const Icon(Icons.chat_bubble_outline, color: Color(0xFF1E9E4A)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Precisa enviar um vídeo longo? Você também pode enviar diretamente para o WhatsApp de fiscalização do Foztrans: ' +
                      SupabaseService.whatsappFoztrans,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _construirFormulario(
      _CategoriaInfo cat, Color cardColor, bool isDark) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Seletor de Linha (só aparece se a categoria exigir linha)
              if (cat.pedeLinha) ...[
                const Text('Linha de Ônibus *',
                    style:
                        TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: _linhaSelecionada,
                  isExpanded: true,
                  decoration: InputDecoration(
                    hintText: 'Selecione a linha…',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                  items: widget.linhas.map((l) {
                    return DropdownMenuItem<String>(
                      value: l.id,
                      child: Text(l.id + ' - ' + l.nome),
                    );
                  }).toList(),
                  onChanged: (val) => setState(() => _linhaSelecionada = val),
                ),
                const SizedBox(height: 14),
              ],

              // 2. Prefixo do Ônibus e Horário (só aparecem quando faz sentido!)
              if (cat.pedePrefixo || cat.pedeHorario) ...[
                Row(
                  children: [
                    if (cat.pedePrefixo)
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Prefixo / Nº do Carro',
                                style: TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 14)),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _prefixoCtrl,
                              decoration: InputDecoration(
                                hintText: 'Ex: 1420 (se souber)',
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10)),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (cat.pedePrefixo && cat.pedeHorario)
                      const SizedBox(width: 10),
                    if (cat.pedeHorario)
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Horário do Ocorrido',
                                style: TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 14)),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _horarioCtrl,
                              readOnly: true,
                              onTap: _selecionarHorario,
                              decoration: InputDecoration(
                                suffixIcon: const Icon(Icons.access_time),
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10)),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
              ],

              // 3. Ponto / Rua ou Parte do App
              if (cat.pedeLocalOuTela) ...[
                Text(cat.labelLocalOuTela,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 6),
                TextField(
                  controller: _localCtrl,
                  decoration: InputDecoration(
                    hintText: 'Digite aqui…',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                ),
                const SizedBox(height: 14),
              ],

              // 4. Descrição detalhada
              const Text('Descrição *',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 6),
              TextField(
                controller: _descCtrl,
                maxLines: 5,
                decoration: InputDecoration(
                  hintText: cat.hintDescricao,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
              const SizedBox(height: 16),

              // 5. Anexo de Foto / Print da tela
              const Text('Foto ou Print da Tela (Opcional)',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 8),
              if (_fotoBytes != null)
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.memory(
                        _fotoBytes!,
                        height: 170,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: 6,
                      right: 6,
                      child: CircleAvatar(
                        backgroundColor: Colors.black87,
                        child: IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => setState(() {
                            _fotoBytes = null;
                            _fotoNome = '';
                          }),
                        ),
                      ),
                    ),
                  ],
                )
              else
                OutlinedButton.icon(
                  icon: const Icon(Icons.add_a_photo_outlined),
                  label: const Text('Anexar imagem da galeria'),
                  onPressed: _escolherFoto,
                ),

              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE53935),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: _enviando
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded),
                  label: Text(
                    _enviando ? 'Enviando…' : 'Enviar para o Foztrans',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 15.5),
                  ),
                  onPressed: _enviando ? null : _enviar,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
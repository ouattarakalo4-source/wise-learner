import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;

// Émulateur Android : 10.0.2.2. Autre : flutter run --dart-define=API_URL=http://IP:8000
const apiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://10.0.2.2:8000');
const navy = Color(0xFF002B5B);
const gold = Color(0xFFFFD700);
const sky = Color(0xFFEAF6FF);

void main() => runApp(const WiseApp());

class WiseApp extends StatelessWidget {
  const WiseApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Wise Learner',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: navy, primary: navy, secondary: gold),
          scaffoldBackgroundColor: sky,
          appBarTheme: const AppBarTheme(backgroundColor: navy, foregroundColor: Colors.white),
          useMaterial3: true,
        ),
        home: const HomePage(),
      );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool loading = false;
  String? error;

  Future<void> pickAndProcess() async {
    final pick = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf'], withData: true);
    if (pick == null || pick.files.single.bytes == null) return;
    final f = pick.files.single;
    setState(() { loading = true; error = null; });
    try {
      final req = http.MultipartRequest('POST', Uri.parse('$apiUrl/process'))
        ..files.add(http.MultipartFile.fromBytes('file', f.bytes!, filename: f.name));
      final res = await http.Response.fromStream(await req.send().timeout(const Duration(seconds: 120)));
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      if (res.statusCode != 200) throw Exception(body['detail'] ?? 'Erreur serveur');
      if (!mounted) return;
      Navigator.push(context, MaterialPageRoute(builder: (_) => ResultPage(title: f.name, data: body)));
    } catch (e) {
      setState(() => error = 'Échec : ${e.toString().replaceFirst('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Wise Learner')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('🎓', style: TextStyle(fontSize: 64)),
              const SizedBox(height: 12),
              const Text('Apprenez plus intelligemment', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: navy)),
              const SizedBox(height: 8),
              const Text('Importez un PDF : résumé, audio et quiz.', textAlign: TextAlign.center),
              const SizedBox(height: 28),
              if (loading) ...[const CircularProgressIndicator(), const SizedBox(height: 12), const Text('Analyse IA en cours...')]
              else FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: gold, foregroundColor: navy, padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16)),
                onPressed: pickAndProcess,
                icon: const Icon(Icons.upload_file),
                label: const Text('Importer un PDF'),
              ),
              if (error != null) Padding(padding: const EdgeInsets.only(top: 16), child: Text(error!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center)),
            ]),
          ),
        ),
      );
}

class ResultPage extends StatelessWidget {
  final String title;
  final Map<String, dynamic> data;
  const ResultPage({super.key, required this.title, required this.data});

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 3,
        child: Scaffold(
          appBar: AppBar(
            title: Text(title, overflow: TextOverflow.ellipsis),
            bottom: const TabBar(labelColor: gold, unselectedLabelColor: Colors.white70, indicatorColor: gold, tabs: [
              Tab(icon: Icon(Icons.article), text: 'Résumé'),
              Tab(icon: Icon(Icons.headphones), text: 'Audio'),
              Tab(icon: Icon(Icons.quiz), text: 'Quiz'),
            ]),
          ),
          body: TabBarView(children: [
            SingleChildScrollView(padding: const EdgeInsets.all(20), child: Text(data['summary'] ?? '', style: const TextStyle(fontSize: 16, height: 1.6))),
            AudioTab(text: data['summary'] ?? ''),
            QuizTab(questions: List<Map<String, dynamic>>.from(data['questions'] ?? [])),
          ]),
        ),
      );
}

class AudioTab extends StatefulWidget {
  final String text;
  const AudioTab({super.key, required this.text});
  @override
  State<AudioTab> createState() => _AudioTabState();
}

class _AudioTabState extends State<AudioTab> {
  final tts = FlutterTts();
  bool playing = false;

  @override
  void initState() {
    super.initState();
    tts.setLanguage('fr-FR');
    tts.setCompletionHandler(() { if (mounted) setState(() => playing = false); });
  }

  @override
  void dispose() { tts.stop(); super.dispose(); }

  Future<void> toggle() async {
    if (playing) { await tts.stop(); setState(() => playing = false); }
    else { setState(() => playing = true); await tts.speak(widget.text); }
  }

  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Leçon audio 🎧', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: navy)),
          const SizedBox(height: 20),
          IconButton.filled(
            iconSize: 56,
            style: IconButton.styleFrom(backgroundColor: gold, foregroundColor: navy),
            onPressed: toggle,
            icon: Icon(playing ? Icons.stop : Icons.play_arrow),
          ),
        ]),
      );
}

class QuizTab extends StatefulWidget {
  final List<Map<String, dynamic>> questions;
  const QuizTab({super.key, required this.questions});
  @override
  State<QuizTab> createState() => _QuizTabState();
}

class _QuizTabState extends State<QuizTab> {
  int i = 0, score = 0;
  int? sel;
  bool done = false;

  @override
  Widget build(BuildContext context) {
    final qs = widget.questions;
    if (qs.isEmpty) return const Center(child: Text('Aucune question générée.'));
    if (done) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('$score / ${qs.length}', style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w700, color: navy)),
          Text(score >= qs.length * 0.7 ? 'Excellent travail !' : 'Continuez, vous progressez !'),
          const SizedBox(height: 16),
          FilledButton(onPressed: () => setState(() { i = 0; score = 0; sel = null; done = false; }), child: const Text('Recommencer')),
        ]),
      );
    }
    final q = qs[i];
    final opts = List<String>.from(q['options']);
    final ans = q['answer'] as int;
    return ListView(padding: const EdgeInsets.all(20), children: [
      Text('Question ${i + 1}/${qs.length}', style: const TextStyle(color: Colors.grey)),
      const SizedBox(height: 8),
      Text(q['q'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: navy)),
      const SizedBox(height: 16),
      for (var k = 0; k < opts.length; k++)
        Card(
          color: sel == null ? Colors.white : k == ans ? Colors.green.shade100 : k == sel ? Colors.red.shade100 : Colors.white,
          child: ListTile(
            title: Text(opts[k]),
            onTap: sel != null ? null : () => setState(() { sel = k; if (k == ans) score++; }),
          ),
        ),
      if (sel != null) ...[
        Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(sel == ans ? 'Correct !' : 'Incorrect. ${q['explanation'] ?? ''}')),
        FilledButton(
          onPressed: () => setState(() { if (i + 1 < qs.length) { i++; sel = null; } else { done = true; } }),
          child: Text(i + 1 < qs.length ? 'Suivant' : 'Terminer'),
        ),
      ],
    ]);
  }
}

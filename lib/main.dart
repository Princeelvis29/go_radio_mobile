import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const GoRadioApp());
}

class GoRadioApp extends StatelessWidget {
  const GoRadioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GO RADIO',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F172A), // Slate 900
        primaryColor: const Color(0xFFEF4444), // Red 500
        fontFamily: 'sans-serif',
      ),
      home: const RadioScreen(),
    );
  }
}

class RadioScreen extends StatefulWidget {
  const RadioScreen({super.key});

  @override
  State<RadioScreen> createState() => _RadioScreenState();
}

class _RadioScreenState extends State<RadioScreen> with SingleTickerProviderStateMixin {
  late AudioPlayer _audioPlayer;
  bool _isPlaying = false;
  bool _isLoading = false;
  
  // API and Stream Data
  final String _streamUrl = 'https://online.goradio.com.ng/listen/gr/radio.mp3';
  final String _apiUrl = 'https://online.goradio.com.ng/api/nowplaying/1';
  final String _whatsappUrl = 'https://wa.me/2348134839763';
  final String _websiteUrl = 'https://online.goradio.com.ng';

  // Metadata State
  String _songTitle = 'Loading stream...';
  String _artistName = 'Connecting to Go Radio';
  String? _albumArtUrl;
  Timer? _metadataTimer;
  
  // Animation for "Live" indicator
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _initAudio();
    _fetchNowPlaying();
    
    // Poll API every 15 seconds matching the web configuration
    _metadataTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      _fetchNowPlaying();
    });

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
  }

  void _initAudio() {
    _audioPlayer.playerStateStream.listen((state) {
      setState(() {
        _isPlaying = state.playing;
        _isLoading = state.processingState == ProcessingState.buffering ||
                     state.processingState == ProcessingState.loading;
      });
    });
  }

  Future<void> _fetchNowPlaying() async {
    try {
      final response = await http.get(Uri.parse(_apiUrl));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _songTitle = data['now_playing']['song']['title'] ?? 'Unknown Title';
          _albumArtUrl = data['now_playing']['song']['art'];
          
          if (data['live']['is_live'] == true) {
            _artistName = 'Live DJ: ${data['live']['streamer_name']}';
          } else {
            _artistName = data['now_playing']['song']['artist'] ?? 'Unknown Artist';
          }
        });
      }
    } catch (e) {
      debugPrint('Error fetching metadata: $e');
    }
  }

  Future<void> _togglePlay() async {
    if (_isPlaying) {
      await _audioPlayer.stop();
    } else {
      try {
        setState(() => _isLoading = true);
        // Using a unique timestamp to prevent caching, identical to the web implementation
        final urlWithCacheBust = '$_streamUrl?nocache=${DateTime.now().millisecondsSinceEpoch}';
        await _audioPlayer.setUrl(urlWithCacheBust);
        await _audioPlayer.play();
      } catch (e) {
        setState(() => _isLoading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error playing stream: $e')),
          );
        }
      }
    }
  }

  Future<void> _launchUrl(String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open link')),
        );
      }
    }
  }

  void _shareApp() {
    Share.share('Listen to GO RADIO live right now! Check it out here: $_websiteUrl');
  }

  @override
  void dispose() {
    _metadataTimer?.cancel();
    _pulseController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('GO RADIO LIVE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1.5)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.share, color: Colors.white70),
            onPressed: _shareApp,
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 450),
            padding: const EdgeInsets.all(32.0),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B), // Slate 800
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                )
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top Logo
                Image.asset(
                  'assets/logo.png',
                  height: 60,
                  errorBuilder: (context, error, stackTrace) => const SizedBox(height: 60),
                ),
                const SizedBox(height: 24),

                // Live Indicator
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FadeTransition(
                      opacity: _pulseController,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: const BoxDecoration(
                          color: Color(0xFFEF4444),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'LIVE ON AIR',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2.0,
                        color: Color(0xFFD1D5DB), // Gray 300
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Dynamic Album Art
                Container(
                  height: 200,
                  width: 200,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 15,
                        offset: const Offset(0, 5),
                      )
                    ],
                    image: DecorationImage(
                      image: _albumArtUrl != null && _albumArtUrl!.isNotEmpty
                          ? NetworkImage(_albumArtUrl!) as ImageProvider
                          : const AssetImage('assets/logo.png'),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // Now Playing Metadata
                Text(
                  _songTitle,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _artistName,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF9CA3AF), // Gray 400
                  ),
                ),
                const SizedBox(height: 40),

                // Custom Play/Pause Control
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1F2937), // Gray 800
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: GestureDetector(
                    onTap: _isLoading ? null : _togglePlay,
                    child: Container(
                      height: 70,
                      width: 70,
                      decoration: BoxDecoration(
                        color: const Color(0xFFDC2626), // Red 600
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFDC2626).withOpacity(0.4),
                            blurRadius: 15,
                            spreadRadius: 2,
                          )
                        ],
                      ),
                      child: Center(
                        child: _isLoading
                            ? const CircularProgressIndicator(color: Colors.white)
                            : Icon(
                                _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                size: 40,
                                color: Colors.white,
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      // Floating WhatsApp Button
      floatingActionButton: FloatingActionButton(
        onPressed: () => _launchUrl(_whatsappUrl),
        backgroundColor: const Color(0xFF25D366),
        child: const Icon(Icons.chat, color: Colors.white),
      ),
    );
  }
}
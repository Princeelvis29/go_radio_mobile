import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> main() async {
  // ⚠️ MANDATORY: Prevents release build crashes when initializing background audio
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Background Audio & OS Lock Screen Controls
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.goradio.app.channel.audio',
    androidNotificationChannelName: 'Go Radio Live Playback',
    androidNotificationOngoing: true,
    androidShowNotificationBadge: true,
    androidNotificationIcon: 'mipmap/launcher_icon', // 🚨 THIS PREVENTS THE CRASH
  );

  runApp(const GoRadioApp());
}

class GoRadioApp extends StatelessWidget {
  const GoRadioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GO RADIO LIVE',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFEF4444),
          surface: Color(0xFF1E293B),
        ),
      ),
      home: const RadioPlayerScreen(),
    );
  }
}

class RadioPlayerScreen extends StatefulWidget {
  const RadioPlayerScreen({super.key});

  @override
  State<RadioPlayerScreen> createState() => _RadioPlayerScreenState();
}

class _RadioPlayerScreenState extends State<RadioPlayerScreen> {
  // --- Constants ---
  static const String _streamUrl = 'https://online.goradio.com.ng/listen/gr/radio.mp3';
  static const String _azuracastApiUrl = 'https://online.goradio.com.ng/api/nowplaying/1';
  static const String _defaultLogoPath = 'assets/logo.png';

  // --- Audio Player & Timers ---
  late AudioPlayer _audioPlayer;
  Timer? _metadataTimer;
  Timer? _sleepTimer;
  Timer? _countdownTimer;

  // --- State Variables ---
  String _songTitle = 'Loading stream...';
  String _artistName = 'Connecting to Go Radio';
  String? _albumArtUrl;
  List<Map<String, String>> _songHistory = [];
  bool _isLoadingMetaData = true;

  // Sleep Timer State
  int _selectedSleepMinutes = 0;
  int _sleepSecondsRemaining = 0;

  // Section Toggles
  bool _showHistory = false;
  bool _showSchedule = false;

  // --- Program Schedule Data ---
  final List<Map<String, String>> _programSchedule = const [
    {'time': '06:00 - 10:00', 'title': 'Morning Drive'},
    {'time': '10:00 - 14:00', 'title': 'Midday Groove'},
    {'time': '14:00 - 18:00', 'title': 'Afternoon Cruise'},
    {'time': '18:00 - 22:00', 'title': 'Evening Lounge'},
    {'time': '22:00 - 06:00', 'title': 'AutoDJ / Night Mix'},
  ];

  // --- External Radio Directories ---
  final List<Map<String, String>> _directories = const [
    {'name': 'TuneIn', 'url': 'https://tunein.com/radio/GoRadio-ng-s353013/'},
    {'name': 'MyTuner', 'url': 'https://mytuner-radio.com/radio/goradio-ng-518335/'},
    {'name': 'Streema', 'url': 'https://streema.com/radios/GoRadio_ng'},
    {'name': 'OnlineRadioBox', 'url': 'https://onlineradiobox.com/ng/go/'},
    {'name': 'GetmeRadio', 'url': 'https://www.getmeradio.com/stations/goradiong-11529'},
    {'name': 'RadioLine', 'url': 'https://www.radioline.co/en/radios/goradio_ng'},
    {'name': 'Live Radio Dublin', 'url': 'https://www.liveradio.ie/stations/goradio'},
    {'name': 'Live Radio UK', 'url': 'https://www.liveradio.uk/stations/goradio'},
    {'name': 'Radio Guide', 'url': 'https://www.radioguide.fm/internet-radio-nigeria/goradio-ng'},
    {'name': 'Radio Plug', 'url': 'https://www.radioplug.co.uk/channel/GoRad-ion'},
    {'name': 'Online Radio Play', 'url': 'https://online-radio-play.com/r112768_goradio_ng'},
    {'name': 'Forward My Stream', 'url': 'https://forwardmystream.com/station/goradio'},
    {'name': 'The OneStop Radio', 'url': 'https://theonestopradio.com/radio/goradio%20ng%20ng'},
    {'name': 'World Radio Browser', 'url': 'https://www.radio-browser.info/search?page=1&order=changetimestamp&reverse=true&hidebroken=false&name=goradio%20ng'},
    {'name': 'Radio.net', 'url': 'https://www.radio.net/s/goradiong'},
    {'name': 'Radio Nigeria', 'url': 'https://www.radio-nigeria.com/goradio-ng'},
    {'name': 'Listen Online Radio', 'url': 'https://listenonlineradio.com/ng/goradio-ng'},
    {'name': 'Radoxo Radio', 'url': 'https://radoxo.com/nigeria/goradio-ng'},
  ];

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _initAudioPlayer();
    _fetchNowPlaying();
    _metadataTimer = Timer.periodic(const Duration(seconds: 15), (_) => _fetchNowPlaying());
  }

  // --- Initialize Audio with MediaItem Tag for Background / Lock Screen ---
  Future<void> _initAudioPlayer() async {
    try {
      await _setAudioSourceWithMetadata();
    } catch (e) {
      debugPrint('Error loading audio stream: $e');
    }
  }

  Future<void> _setAudioSourceWithMetadata() async {
    try {
      await _audioPlayer.setAudioSource(
        AudioSource.uri(
          Uri.parse(_streamUrl),
          tag: MediaItem(
            id: 'goradio_live_stream',
            album: 'GO RADIO LIVE',
            title: _songTitle,
            artist: _artistName,
            artUri: _albumArtUrl != null && _albumArtUrl!.isNotEmpty
                ? Uri.tryParse(_albumArtUrl!)
                : null,
          ),
        ),
        preload: false,
      );
    } catch (e) {
      debugPrint('Error setting audio source metadata: $e');
    }
  }

  @override
  void dispose() {
    _metadataTimer?.cancel();
    _sleepTimer?.cancel();
    _countdownTimer?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  // --- Fetch AzuraCast Live Metadata ---
  Future<void> _fetchNowPlaying() async {
    try {
      final response = await http.get(Uri.parse(_azuracastApiUrl)).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        final nowPlaying = data['now_playing'];
        final song = nowPlaying?['song'];
        final live = data['live'];

        final String title = song?['title'] ?? 'GO RADIO LIVE';
        final bool isLive = live?['is_live'] ?? false;
        final String streamer = live?['streamer_name'] ?? '';
        final String artist = isLive && streamer.isNotEmpty
            ? 'Live DJ: $streamer'
            : (song?['artist'] ?? 'GO RADIO');
        final String? artUrl = song?['art'];

        // Parse History
        final List historyList = data['song_history'] ?? [];
        final List<Map<String, String>> parsedHistory = [];
        for (var item in historyList.take(5)) {
          final hSong = item['song'];
          if (hSong != null) {
            parsedHistory.add({
              'title': hSong['title'] ?? 'Unknown Track',
              'artist': hSong['artist'] ?? 'Unknown Artist',
              'art': hSong['art'] ?? '',
            });
          }
        }

        if (mounted) {
          setState(() {
            _songTitle = title;
            _artistName = artist;
            _albumArtUrl = artUrl;
            _songHistory = parsedHistory;
            _isLoadingMetaData = false;
          });

          // Update lock screen notification metadata if stream is paused
          if (!_audioPlayer.playing) {
            _setAudioSourceWithMetadata();
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching metadata: $e');
      if (mounted) {
        setState(() {
          _isLoadingMetaData = false;
        });
      }
    }
  }

  // --- External URL Helper ---
  Future<void> _launchExternalUrl(String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not launch $url')),
        );
      }
    }
  }

  // --- Live Share Button Functionality ---
  void _shareApp() {
    final String trackInfo = _artistName.isNotEmpty && _artistName != 'Connecting to Go Radio'
        ? '$_songTitle by $_artistName'
        : _songTitle;
        
    Share.share(
      "I'm listening to Go Radio Live! Currently playing: $trackInfo. Download the app here: https://live.goradio.com.ng",
    );
  }

  // --- Sleep Timer Handling ---
  void _setSleepTimer(int minutes) {
    _sleepTimer?.cancel();
    _countdownTimer?.cancel();

    setState(() {
      _selectedSleepMinutes = minutes;
      _sleepSecondsRemaining = minutes * 60;
    });

    if (minutes == 0) return;

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        if (_sleepSecondsRemaining > 0) {
          _sleepSecondsRemaining--;
        } else {
          timer.cancel();
        }
      });
    });

    _sleepTimer = Timer(Duration(minutes: minutes), () async {
      await _audioPlayer.pause();
      if (mounted) {
        setState(() {
          _selectedSleepMinutes = 0;
          _sleepSecondsRemaining = 0;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sleep timer finished. Playback paused.')),
        );
      }
    });
  }

  String _formatTimerDisplay(int totalSeconds) {
    final m = totalSeconds ~/ 60;
    final s = totalSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'GO RADIO LIVE',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: 'Share GO RADIO',
            onPressed: _shareApp,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _launchExternalUrl('https://wa.me/2348134839763'),
        backgroundColor: const Color(0xFF25D366),
        child: const Icon(Icons.chat, color: Colors.white, size: 28),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 450),
            padding: const EdgeInsets.all(20.0),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white10),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black45,
                  blurRadius: 15,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Station Logo
                Image.asset(
                  _defaultLogoPath,
                  height: 60,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
                ),
                const SizedBox(height: 12),

                // Live Indicator Badge
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: Colors.redAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'LIVE ON AIR',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Album Artwork
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    width: 220,
                    height: 220,
                    color: Colors.black26,
                    child: _albumArtUrl != null && _albumArtUrl!.isNotEmpty
                        ? Image.network(
                            _albumArtUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                Image.asset(_defaultLogoPath, fit: BoxFit.cover),
                          )
                        : Image.asset(_defaultLogoPath, fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(height: 20),

                // Now Playing Metadata Display
                Text(
                  _songTitle,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _artistName,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.white60,
                  ),
                ),
                const SizedBox(height: 24),

                // Audio Controls Block
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    children: [
                      // Stream Playback StreamBuilder
                      StreamBuilder<PlayerState>(
                        stream: _audioPlayer.playerStateStream,
                        builder: (context, snapshot) {
                          final playerState = snapshot.data;
                          final processingState = playerState?.processingState;
                          final playing = playerState?.playing ?? false;

                          if (processingState == ProcessingState.loading ||
                              processingState == ProcessingState.buffering) {
                            return const SizedBox(
                              height: 64,
                              width: 64,
                              child: CircularProgressIndicator(color: Color(0xFFEF4444)),
                            );
                          }

                          return Container(
                            decoration: const BoxDecoration(
                              color: Color(0xFFEF4444),
                              shape: BoxShape.circle,
                            ),
                            child: IconButton(
                              iconSize: 42,
                              icon: Icon(
                                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                color: Colors.white,
                              ),
                              onPressed: () async {
                                if (playing) {
                                  await _audioPlayer.pause();
                                } else {
                                  if (_audioPlayer.audioSource == null) {
                                    await _setAudioSourceWithMetadata();
                                  }
                                  await _audioPlayer.play();
                                }
                              },
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 16),

                      // Sleep Timer Selector Row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'SLEEP TIMER:',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.white60,
                              letterSpacing: 1,
                            ),
                          ),
                          DropdownButton<int>(
                            value: _selectedSleepMinutes,
                            dropdownColor: const Color(0xFF1E293B),
                            underline: const SizedBox.shrink(),
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                            items: const [
                              DropdownMenuItem(value: 0, child: Text('Off')),
                              DropdownMenuItem(value: 15, child: Text('15 Mins')),
                              DropdownMenuItem(value: 30, child: Text('30 Mins')),
                              DropdownMenuItem(value: 60, child: Text('1 Hour')),
                              DropdownMenuItem(value: 90, child: Text('90 Mins')),
                            ],
                            onChanged: (value) {
                              if (value != null) _setSleepTimer(value);
                            },
                          ),
                        ],
                      ),
                      if (_selectedSleepMinutes > 0)
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            'Pausing in ${_formatTimerDisplay(_sleepSecondsRemaining)}',
                            style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Collapsible Recently Played Section
                _buildAccordionHeader(
                  title: 'Recently Played',
                  isOpen: _showHistory,
                  onTap: () => setState(() => _showHistory = !_showHistory),
                ),
                if (_showHistory)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: _songHistory.isEmpty
                        ? const Text(
                            'No recent history available',
                            style: TextStyle(color: Colors.white38, fontSize: 12),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _songHistory.length,
                            separatorBuilder: (_, __) => const Divider(color: Colors.white10),
                            itemBuilder: (context, index) {
                              final track = _songHistory[index];
                              return Row(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: track['art'] != null && track['art']!.isNotEmpty
                                        ? Image.network(
                                            track['art']!,
                                            width: 38,
                                            height: 38,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) => Image.asset(
                                              _defaultLogoPath,
                                              width: 38,
                                              height: 38,
                                            ),
                                          )
                                        : Image.asset(_defaultLogoPath, width: 38, height: 38),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          track['title'] ?? '',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            color: Colors.white,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          track['artist'] ?? '',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.white54,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                  ),
                const SizedBox(height: 12),

                // Collapsible Program Schedule Section
                _buildAccordionHeader(
                  title: 'Program Schedule',
                  isOpen: _showSchedule,
                  onTap: () => setState(() => _showSchedule = !_showSchedule),
                ),
                if (_showSchedule)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _programSchedule.length,
                      separatorBuilder: (_, __) => const Divider(color: Colors.white10),
                      itemBuilder: (context, index) {
                        final item = _programSchedule[index];
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              item['time'] ?? '',
                              style: const TextStyle(
                                color: Colors.redAccent,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              item['title'] ?? '',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 24),

                // Share App Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white10,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.share, size: 18, color: Colors.white),
                    label: const Text(
                      'SHARE GO RADIO',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    onPressed: _shareApp,
                  ),
                ),

                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Divider(color: Colors.white10),
                ),

                // External Radio Directories Grid Section
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'LISTEN ON YOUR FAVORITE APP',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.white54,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 3.2,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: _directories.length,
                  itemBuilder: (context, index) {
                    final dir = _directories[index];
                    return InkWell(
                      onTap: () => _launchExternalUrl(dir['url']!),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white10),
                        ),
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text(
                          dir['name']!,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    );
                  },
                ),

                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Divider(color: Colors.white10),
                ),

                // Contact Information Footer
                const Text(
                  'CONTACT US',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.white54,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () => _launchExternalUrl('mailto:support@goradio.com.ng'),
                  child: const Text(
                    'support@goradio.com.ng',
                    style: TextStyle(color: Colors.redAccent, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 4),
                InkWell(
                  onTap: () => _launchExternalUrl('tel:+2348134839763'),
                  child: const Text(
                    '+234 813 483 9763',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 4),
                InkWell(
                  onTap: () => _launchExternalUrl('tel:+2348050344913'),
                  child: const Text(
                    '+234 805 034 4913',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '© GO RADIO. All Rights Reserved.',
                  style: TextStyle(color: Colors.white30, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- Accordion Header Helper ---
  Widget _buildAccordionHeader({
    required String title,
    required bool isOpen,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title.toUpperCase(),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.white70,
                letterSpacing: 1,
              ),
            ),
            Icon(
              isOpen ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
              color: Colors.white70,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
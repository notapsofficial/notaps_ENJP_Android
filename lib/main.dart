import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:sensors_plus/sensors_plus.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:in_app_review/in_app_review.dart';
import 'subscription_manager.dart';
import 'subscription_screen.dart';

// enumをトップレベルに移動し、reviewを追加
enum Level { level1, level2, level3, level4, idiom, business, review, quo }

// main関数を更新し、NotapAppを直接呼び出す
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NotapApp());
}

// NotapAppがアプリのルートウィジェットになる
class NotapApp extends StatefulWidget {
  const NotapApp({super.key});

  @override
  State<NotapApp> createState() => _NotapAppState();
}

// _NotapAppStateにスプラッシュスクリーンと全設定の管理ロジックを統合
class _NotapAppState extends State<NotapApp> with TickerProviderStateMixin {
  // --- スプラッシュスクリーンの状態 ---
  late AnimationController _splashController;
  late Animation<double> _splashFadeAnimation;
  bool _showSplash = true;
  bool _settingsLoaded = false;

  bool _showTutorial = false;
  bool _showSubscription = false;

  // --- アプリ全体の設定 ---
  int _themeStep = 0;
  bool _showEnglishFirst = true;
  int _gradientIndex = 0;
  int _displayModeIndex = 0;
  bool _isMuted = true;
  int _speechMode = 0;
  Level _currentLevel = Level.level1;
  Duration _portraitInterval = const Duration(milliseconds: 1000);
  Duration _landscapeInterval = const Duration(milliseconds: 3000);

  // --- 単語データ管理 ---
  List<Map<String, dynamic>> _allWords = [];
  List<Map<String, dynamic>> _currentWordPairs = [];
  List<String> _reviewWordIds = [];

  @override
  void initState() {
    super.initState();
    // スプラッシュスクリーンのアニメーション設定
    _splashController = AnimationController(
      duration: const Duration(milliseconds: 1800),
      vsync: this,
    );
    _splashFadeAnimation = Tween<double>(begin: 0.0, end: 1.0)
        .chain(CurveTween(curve: Curves.easeInOut))
        .animate(_splashController);

    _splashController.forward();

    // 設定と単語データを読み込み、スプラッシュ画面を終了
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await _loadSettings();
    await _loadAllWordsOnce();
    _filterWordsForCurrentLevel();

    // サブスクリプション状態をチェック
    final subscriptionManager = SubscriptionManager();
    await subscriptionManager.initialize();
    
    // テスト用: サブスクリプション画面を強制表示
      setState(() {
        _showSubscription = true;
      });
    
    // 元のコード（テスト後に戻す）
    // if (!subscriptionManager.canUseApp()) {
    //   setState(() {
    //     _showSubscription = true;
    //   });
    // }

    Future.delayed(const Duration(milliseconds: 1800), () {
      if (mounted) {
        setState(() {
          _showSplash = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _splashController.dispose();
    super.dispose();
  }

  // --- 設定の保存 ---
  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('themeStep', _themeStep);
    await prefs.setBool('showEnglishFirst', _showEnglishFirst);
    await prefs.setInt('gradientIndex', _gradientIndex);
    await prefs.setInt('displayModeIndex', _displayModeIndex);
    await prefs.setBool('isMuted', _isMuted);
    await prefs.setInt('speechMode', _speechMode);
    await prefs.setInt('currentLevel', _currentLevel.index);
    await prefs.setInt('portraitInterval', _portraitInterval.inMilliseconds);
    await prefs.setInt('landscapeInterval', _landscapeInterval.inMilliseconds);
    await prefs.setStringList('reviewWordIds', _reviewWordIds);
  }

  // --- 設定の読み込み ---
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _themeStep = prefs.getInt('themeStep') ?? 0;
      _showEnglishFirst = prefs.getBool('showEnglishFirst') ?? true;
      _gradientIndex = prefs.getInt('gradientIndex') ?? 0;
      _displayModeIndex = prefs.getInt('displayModeIndex') ?? 0;
      _isMuted = prefs.getBool('isMuted') ?? true;
      _speechMode = prefs.getInt('speechMode') ?? 0;
      _currentLevel = Level.values[prefs.getInt('currentLevel') ?? 0];
      _portraitInterval =
          Duration(milliseconds: prefs.getInt('portraitInterval') ?? 1000);
      _landscapeInterval =
          Duration(milliseconds: prefs.getInt('landscapeInterval') ?? 3000);
      _reviewWordIds = prefs.getStringList('reviewWordIds') ?? [];

      final hasSeenTutorial = prefs.getBool('hasSeenTutorial') ?? false;
      if (!hasSeenTutorial) {
        _showTutorial = true;
      }

      _settingsLoaded = true;
    });
  }

  Future<void> _onTutorialFinished() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hasSeenTutorial', true);
    if (mounted) {
      setState(() {
        _showTutorial = false;
      });
    }
  }

  void _onSubscriptionComplete() {
    setState(() {
      _showSubscription = false;
      _showTutorial = true; // サブスク完了後に必ずチュートリアルを表示
    });
  }

  Future<void> _loadAllWordsOnce() async {
    try {
      final String response =
          await rootBundle.loadString('assets/word_finalized_0613.json');
      final List<dynamic> data = json.decode(response);
      _allWords = data.asMap().entries.map((entry) {
        int idx = entry.key;
        Map<String, dynamic> val = Map<String, dynamic>.from(entry.value);
        val['id'] = val['en'] ?? 'word_$idx';
        return val;
      }).toList();
      print("All words loaded successfully: ${_allWords.length} words");
    } catch (e) {
      print('Error loading JSON: $e');
    }
  }

  void _filterWordsForCurrentLevel() {
    List<Map<String, dynamic>> filteredWords = [];
    if (_currentLevel == Level.review) {
      filteredWords =
          _allWords.where((word) => _reviewWordIds.contains(word['id'])).toList();
    } else {
      String levelFilter;
      switch (_currentLevel) {
        case Level.idiom:
          levelFilter = 'idiom';
          break;
        case Level.business:
          levelFilter = 'business';
          break;
        case Level.quo:
          levelFilter = 'quo';
          break;
        case Level.level1:
          levelFilter = '1';
          break;
        case Level.level2:
          levelFilter = '2';
          break;
        case Level.level3:
          levelFilter = '3';
          break;
        case Level.level4:
          levelFilter = '4';
          break;
        case Level.review:
          levelFilter = '';
          break;
      }
      if (levelFilter.isNotEmpty) {
        filteredWords = _allWords
            .where((item) => item['level']?.toString().trim() == levelFilter)
            .toList();
      }
    }

    filteredWords.shuffle();
    print("Filtered for $_currentLevel: ${filteredWords.length} words");

    setState(() {
      _currentWordPairs = filteredWords;
    });
  }

  void _toggleTheme() {
    setState(() {
      _themeStep = (_themeStep + 1) % 2;
    });
    _saveSettings();
  }

  void _toggleLanguageOrder() {
    setState(() {
      _showEnglishFirst = !_showEnglishFirst;
    });
    _saveSettings();
  }

  void _cycleGradientIndex() {
    setState(() {
      _gradientIndex = (_gradientIndex + 1) % 6;
    });
    _saveSettings();
  }

  void _cycleDisplayMode() {
    setState(() {
      if (_currentLevel == Level.business) {
        _displayModeIndex = (_displayModeIndex + 1) % 2;
      } else {
        _displayModeIndex = (_displayModeIndex + 1) % 3;
      }
    });
    _saveSettings();
  }

  void _updateSpeechMode() {
    setState(() {
      if (_isMuted) {
        _isMuted = false;
        _speechMode = 1;
      } else {
        _speechMode = (_speechMode + 1) % 4;
        if (_speechMode == 0) {
          _isMuted = true;
        }
      }
    });
    _saveSettings();
  }

  void _cycleLevel() {
    setState(() {
      _currentLevel = Level.values[(_currentLevel.index + 1) % Level.values.length];
      _displayModeIndex = 0;
      _filterWordsForCurrentLevel();
    });
    _saveSettings();
  }

  void _updateInterval(Duration newDuration, bool isPortrait) {
    setState(() {
      if (isPortrait) {
        _portraitInterval = newDuration;
      } else {
        _landscapeInterval = newDuration;
      }
    });
    _saveSettings();
  }

  void _addReviewWord(String wordId) {
    if (!_reviewWordIds.contains(wordId)) {
      setState(() {
        _reviewWordIds.add(wordId);
      });
      _saveSettings();
    }
  }

  void _removeReviewWord(String wordId) {
    if (_reviewWordIds.contains(wordId)) {
      setState(() {
        _reviewWordIds.remove(wordId);
        if (_currentLevel == Level.review) {
          _filterWordsForCurrentLevel();
        }
      });
      _saveSettings();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = _themeStep == 1;

    return MaterialApp(
      title: 'NoTap App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: isDark ? Brightness.dark : Brightness.light,
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: _showSplash || !_settingsLoaded
          ? Scaffold(
              backgroundColor: Colors.white,
              body: Center(
                child: FadeTransition(
                  opacity: _splashFadeAnimation,
                  child: Text(
                    'notaps',
                    style: TextStyle(
                      fontSize: 82,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Georgia',
                      foreground: Paint()
                        ..shader = LinearGradient(
                          colors: [
                            Color(0xFF2ECC71),
                            Color(0xFF58D68D),
                            Color(0xFF48C9B0),
                            Color(0xFF5DADE2)
                          ],
                          stops: [0.0, 0.3, 0.6, 1.0],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ).createShader(Rect.fromLTWH(0.0, 0.0, 200.0, 70.0)),
                    ),
                  ),
                ),
              ),
            )
          : Stack(
              children: [
                if (_showSubscription)
                  SubscriptionScreen(
                    onSubscriptionComplete: _onSubscriptionComplete,
                  )
                else
                  WordDisplayScreen(
                    wordPairs: _currentWordPairs,
                    onToggleTheme: _toggleTheme,
                    showEnglishFirst: _showEnglishFirst,
                    onToggleLanguageOrder: _toggleLanguageOrder,
                    gradientIndex: _gradientIndex,
                    onCycleGradientIndex: _cycleGradientIndex,
                    displayModeIndex: _displayModeIndex,
                    onCycleDisplayMode: _cycleDisplayMode,
                    isMuted: _isMuted,
                    speechMode: _speechMode,
                    onUpdateSpeechMode: _updateSpeechMode,
                    currentLevel: _currentLevel,
                    onCycleLevel: _cycleLevel,
                    portraitInterval: _portraitInterval,
                    landscapeInterval: _landscapeInterval,
                    onUpdateInterval: _updateInterval,
                    onAddReviewWord: _addReviewWord,
                    onRemoveReviewWord: _removeReviewWord,
                  ),
                if (_showTutorial && !_showSubscription)
                  TutorialOverlay(
                    onFinished: _onTutorialFinished,
                  ),
              ],
            ),
    );
  }
}

class WordDisplayScreen extends StatefulWidget {
  final List<Map<String, dynamic>> wordPairs;
  final VoidCallback onToggleTheme;
  final bool showEnglishFirst;
  final VoidCallback onToggleLanguageOrder;
  final int gradientIndex;
  final VoidCallback onCycleGradientIndex;
  final int displayModeIndex;
  final VoidCallback onCycleDisplayMode;
  final bool isMuted;
  final int speechMode;
  final VoidCallback onUpdateSpeechMode;
  final Level currentLevel;
  final VoidCallback onCycleLevel;
  final Duration portraitInterval;
  final Duration landscapeInterval;
  final Function(Duration, bool) onUpdateInterval;
  final Function(String) onAddReviewWord;
  final Function(String) onRemoveReviewWord;

  const WordDisplayScreen({
    super.key,
    required this.wordPairs,
    required this.onToggleTheme,
    required this.showEnglishFirst,
    required this.onToggleLanguageOrder,
    required this.gradientIndex,
    required this.onCycleGradientIndex,
    required this.displayModeIndex,
    required this.onCycleDisplayMode,
    required this.isMuted,
    required this.speechMode,
    required this.onUpdateSpeechMode,
    required this.currentLevel,
    required this.onCycleLevel,
    required this.portraitInterval,
    required this.landscapeInterval,
    required this.onUpdateInterval,
    required this.onAddReviewWord,
    required this.onRemoveReviewWord,
  });

  @override
  State<WordDisplayScreen> createState() => _WordDisplayScreenState();
}

class _WordDisplayScreenState extends State<WordDisplayScreen>
    with TickerProviderStateMixin {
  bool _isOntapsMode = false;
  bool isHandheld = false;
  StreamSubscription<AccelerometerEvent>? _accelSubscription;
  int? _lastSpokenIndex;
  bool? _lastSpokenShowEnglish;

  final FlutterTts _flutterTts = FlutterTts();
  bool _showOverlayIcons = true;
  Timer? _overlayHideTimer;
  bool _canShowIcons = true;

  int index = 0;
  bool showEnglish = true;
  Timer? _timer;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  String _currentTime = '';
  Timer? _clockTimer;

  late Duration _currentInterval;

  List<Map<String, dynamic>> _history = [];
  bool _showHistory = false;
  final ScrollController _scrollController = ScrollController();
  late AnimationController _historyAnimationController;
  late Animation<double> _historyAnimation;

  OverlayEntry? _overlayEntry;
  final LayerLink _iconBarLayerLink = LayerLink();

  int _viewedCount = 0;
  int _totalWordsInLevel = 0;

  LinearGradient _getStyleGradient() {
    final List<LinearGradient> _gradients = [
      LinearGradient(
        colors: [
          Color(0xFF2ECC71),
          Color(0xFF58D68D),
          Color(0xFF48C9B0),
          Color(0xFF5DADE2)
        ],
        stops: [0.0, 0.3, 0.6, 1.0],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      LinearGradient(
        colors: [Color(0xFFFF66B2), Color(0xFFFFC0CB)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      LinearGradient(
        colors: [Color(0xFF3399FF), Color(0xFF66CCFF)],
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
      ),
      LinearGradient(
        colors: [Color(0xFF8E2DE2), Color(0xFFB388FF)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      LinearGradient(
        colors: [Color(0xFFFFA17F), Color(0xFFFF6A00)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      LinearGradient(
        colors: [Color(0xFFB24592), Color(0xFFF15F79)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ];
    return _gradients[widget.gradientIndex % _gradients.length];
  }

  int get _currentIndex => index;
  set _currentIndex(int value) {
    index = value;
  }

  // ★修正点：戻るボタンのロジックを全面的に修正
  void _previousWord() {
    // 最初の単語の英語表示より前には戻れない
    if (index == 0 && showEnglish) {
      return;
    }

    _fadeController.reverse().then((_) {
      if (!mounted) return;

      setState(() {
        if (showEnglish) {
          // 現在が英語表示の場合：前の単語に戻り、日本語表示にする
          index--;
          showEnglish = false;
        } else {
          // 現在が日本語表示の場合：同じ単語の英語表示に戻す
          showEnglish = true;
        }

        // 発話記録をリセット
        _lastSpokenIndex = null;
        _lastSpokenShowEnglish = null;
      });

      _fadeController.forward();
      _speakCurrentWord();
    });
  }

  void _nextWord() {
    if (widget.wordPairs.isEmpty) return;

    _fadeController.reverse().then((_) {
      if (!mounted) return;

      setState(() {
        showEnglish = !showEnglish;

        if (showEnglish) {
          index = (index + 1) % widget.wordPairs.length;
          final currentWord = widget.wordPairs[index];
          _saveProgress(currentWord['id']);
          if (widget.currentLevel != Level.quo) {
            _addToHistory(currentWord);
          }
          _checkAndRequestReview();
        }
        
        _lastSpokenIndex = null;
        _lastSpokenShowEnglish = null;
      });

      _fadeController.forward();

      if (!_isOntapsMode) {
        _startDisplayTimer();
      } else {
        _speakCurrentWord();
      }
    });
  }

  Future<void> _checkAndRequestReview() async {
    final prefs = await SharedPreferences.getInstance();
    bool hasRequestedReview = prefs.getBool('has_requested_review') ?? false;

    if (hasRequestedReview) {
      return;
    }

    int wordViewCount = prefs.getInt('word_view_count') ?? 0;
    wordViewCount++;
    await prefs.setInt('word_view_count', wordViewCount);

    if (wordViewCount >= 50) {
      await prefs.setBool('has_requested_review', true);
      Future.delayed(const Duration(milliseconds: 1500), () {
         if (mounted) {
           _showReviewDialog();
         }
      });
    }
  }

  Future<void> _showReviewDialog() async {
    final InAppReview inAppReview = InAppReview.instance;
    final locale = ui.window.locale.languageCode;

    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(locale == 'ja' ? 'レビューのお願い' : 'Request for Review'),
          content: Text(locale == 'ja' 
              ? 'このアプリを気に入っていただけましたか？\nよろしければレビューで応援をお願いします！'
              : 'Do you like this app?\nPlease consider supporting us with a review!'),
          actions: <Widget>[
            TextButton(
              child: Text(locale == 'ja' ? 'あとで' : 'Later'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text(locale == 'ja' ? 'レビューする' : 'Review'),
              onPressed: () async {
                Navigator.of(context).pop();
                if (await inAppReview.isAvailable()) {
                  inAppReview.requestReview();
                }
              },
            ),
          ],
        );
      },
    );
  }

  void _addToHistory(Map<String, dynamic> word) {
    setState(() {
      _history.insert(0, word);
      if (_history.length > 100) {
        _history.removeLast();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.minScrollExtent,
          duration: Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _toggleHistoryMode() {
    setState(() {
      _showHistory = !_showHistory;
    });

    if (_showHistory) {
      _timer?.cancel();
      _fadeController.stop();
      _historyAnimationController.forward();
    } else {
      _timer?.cancel();
      _historyAnimationController.reverse();
      if (!_isOntapsMode) {
        _startDisplayTimer();
      }
    }
  }

  Widget _buildHistoryList() {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bgColor = isDark ? Colors.black : Colors.white;
    final Color textColor = isDark ? Colors.white : Colors.black;
    final bool isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    if (isLandscape) {
      return GestureDetector(
        onTap: _toggleHistoryMode,
        child: Container(
          color: bgColor,
          child: Column(
            children: [
              Container(
                color: bgColor,
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Recent 100 Sentences',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: textColor),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  itemCount: _history.length,
                  itemBuilder: (context, index) {
                    final Map<String, dynamic> word = _history[index];
                    return ListTile(
                      title: Text(
                        word['sentence_en'] ?? '',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: textColor,
                          fontSize: 18,
                        ),
                      ),
                      subtitle: Text(
                        word['sentence_ja'] ?? '',
                        style: TextStyle(
                          color: textColor,
                          fontSize: 14,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      return Container(
        color: bgColor,
        child: Column(
          children: [
            Container(
              color: bgColor,
              padding: const EdgeInsets.all(16),
              child: Text(
                'Recent 100 Words',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: textColor),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                itemCount: _history.length,
                itemBuilder: (context, index) {
                  final Map<String, dynamic> word = _history[index];
                  return ListTile(
                    title: Text(
                      word['en'] ?? '',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, color: textColor),
                    ),
                    subtitle: Text(
                      '${word['kanji']} / ${word['hiragana']} / ${word['romaji']}',
                      style: TextStyle(color: textColor),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      );
    }
  }

  bool get _currentShowEnglish =>
      widget.showEnglishFirst ? showEnglish : !showEnglish;

  @override
  void initState() {
    super.initState();
    _setupTts();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnimation =
        CurvedAnimation(parent: _fadeController, curve: Curves.easeIn);

    _fadeController.forward();

    _historyAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _historyAnimation = CurvedAnimation(
      parent: _historyAnimationController,
      curve: Curves.easeInOut,
    );

    _historyAnimationController.addStatusListener((status) {
      if (status == AnimationStatus.forward) {
        setState(() => _canShowIcons = false);
      } else if (status == AnimationStatus.dismissed) {
        setState(() => _canShowIcons = true);
      }
    });

    _currentTime = DateFormat('HH:mm').format(DateTime.now());
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      final String formattedTime = DateFormat('HH:mm').format(DateTime.now());
      if (formattedTime != _currentTime) {
        setState(() {
          _currentTime = formattedTime;
        });
      }
    });

    _resetOverlayIconsVisibility();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAndViewedWords();
      setState(() {});
    });

    _accelSubscription =
        accelerometerEvents.listen((AccelerometerEvent event) {
      double magnitude =
          sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
      setState(() {
        isHandheld = (magnitude - 9.8).abs() > 1.5;
      });
    });
  }

  Future<void> _setupTts() async {
    await _flutterTts.setSharedInstance(true);
    await _flutterTts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        [
          IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
          IosTextToSpeechAudioCategoryOptions.mixWithOthers,
        ],
        IosTextToSpeechAudioMode.voicePrompt);

    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.4);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final orientation = MediaQuery.of(context).orientation;
    if (orientation == Orientation.portrait) {
      _currentInterval = widget.portraitInterval;
    } else {
      _currentInterval = widget.landscapeInterval;
    }
    _timer?.cancel();
    if (!_isOntapsMode) {
      _startDisplayTimer();
    }
  }

  @override
  void didUpdateWidget(WordDisplayScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.wordPairs != widget.wordPairs ||
        oldWidget.currentLevel != widget.currentLevel) {
      index = 0;
      _loadAndViewedWords();
      _timer?.cancel();
      if (!_isOntapsMode) {
        _startDisplayTimer();
      }
    }

    if (oldWidget.portraitInterval != widget.portraitInterval ||
        oldWidget.landscapeInterval != widget.landscapeInterval) {
      final orientation = MediaQuery.of(context).orientation;

      final newInterval = (orientation == Orientation.portrait)
          ? widget.portraitInterval
          : widget.landscapeInterval;

      if (_currentInterval != newInterval) {
        setState(() {
          _currentInterval = newInterval;
        });
        _timer?.cancel();
        if (!_isOntapsMode) {
          _startDisplayTimer();
        }
      }
    }
  }

  Future<void> _loadAndViewedWords() async {
    if (widget.currentLevel == Level.review ||
        widget.currentLevel == Level.quo) {
      setState(() {
        _totalWordsInLevel = 0;
        _viewedCount = 0;
      });
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final viewedIds =
        prefs.getStringList('viewedWords_${widget.currentLevel.name}') ?? [];

    setState(() {
      _totalWordsInLevel = widget.wordPairs.length;
      _viewedCount = Set<String>.from(viewedIds).length;
    });
  }

  Future<void> _saveProgress(String wordId) async {
    if (widget.currentLevel == Level.review ||
        widget.currentLevel == Level.quo) return;

    final prefs = await SharedPreferences.getInstance();
    final key = 'viewedWords_${widget.currentLevel.name}';
    final viewedIds = prefs.getStringList(key) ?? [];

    var viewedSet = Set<String>.from(viewedIds);
    if (viewedSet.add(wordId)) {
      await prefs.setStringList(key, viewedSet.toList());
      setState(() {
        _viewedCount = viewedSet.length;
      });
    }
  }

  Future<void> _showResetConfirmationDialog() async {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('進捗のリセット'),
          content: const SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text('このレベルの学習進捗をリセットしますか？'),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('いいえ'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('はい'),
              onPressed: () {
                _resetProgressForCurrentLevel();
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _resetProgressForCurrentLevel() async {
    if (widget.currentLevel == Level.review ||
        widget.currentLevel == Level.quo) return;
    final prefs = await SharedPreferences.getInstance();
    final key = 'viewedWords_${widget.currentLevel.name}';
    await prefs.remove(key);
    await _loadAndViewedWords();
  }

  void _startDisplayTimer() async {
    if (widget.wordPairs.isEmpty) return;
    await _flutterTts.stop();

    if (!_isOntapsMode) {
      _timer?.cancel();
      _timer = Timer(_currentInterval, _nextWord);
    }
    if (!widget.isMuted) {
      _speakCurrentWord();
    }
  }

  void _speakCurrentWord() async {
    if (widget.wordPairs.isEmpty || widget.isMuted) return;

    if (_lastSpokenIndex == index &&
        _lastSpokenShowEnglish == _currentShowEnglish) {
      return;
    }

    _lastSpokenIndex = index;
    _lastSpokenShowEnglish = _currentShowEnglish;

    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    try {
      if (isLandscape) {
        if (_currentShowEnglish) {
          if (widget.speechMode == 1 || widget.speechMode == 3) {
            await _flutterTts.setLanguage("en-US");
            await _flutterTts.setSpeechRate(0.4);
            await _flutterTts.setPitch(1.0);
            await _flutterTts
                .speak(widget.wordPairs[index]['sentence_en'] ?? '');
          }
        } else {
          if (widget.speechMode == 2 || widget.speechMode == 3) {
            await _flutterTts.setLanguage("ja-JP");
            await _flutterTts.setSpeechRate(0.6);
            await _flutterTts.setPitch(1.0);
            await _flutterTts
                .speak(widget.wordPairs[index]['sentence_ja'] ?? '');
          }
        }
      } else {
        if (_currentShowEnglish) {
          if (widget.speechMode == 1 || widget.speechMode == 3) {
            await _flutterTts.setLanguage("en-US");
            await _flutterTts.setSpeechRate(0.4);
            await _flutterTts.setPitch(1.0);
            await _flutterTts.speak(widget.wordPairs[index]['en'] ?? '');
          }
        } else {
          if (widget.speechMode == 2 || widget.speechMode == 3) {
            await _flutterTts.setLanguage("ja-JP");
            String jaTextToSpeak;

            if (widget.currentLevel == Level.business) {
              jaTextToSpeak = widget.wordPairs[index]['kanji'] ?? '';
              await _flutterTts.setSpeechRate(0.4);
              await _flutterTts.setPitch(1.0);
            } else {
              jaTextToSpeak = widget.wordPairs[index]['hiragana'] ?? '';
              if (widget.currentLevel == Level.level1) {
                await _flutterTts.setSpeechRate(0.3);
                await _flutterTts.setPitch(1.2);
              } else {
                await _flutterTts.setSpeechRate(0.4);
                await _flutterTts.setPitch(1.0);
              }
            }
            await _flutterTts.speak(jaTextToSpeak);
          }
        }
      }
    } catch (e) {
      print("Error from TTS: $e");
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _fadeController.dispose();
    _historyAnimationController.dispose();
    _clockTimer?.cancel();
    _overlayHideTimer?.cancel();
    _accelSubscription?.cancel();
    _overlayEntry?.remove();
    super.dispose();
  }

  void _resetOverlayIconsVisibility() {
    if (!_showOverlayIcons) {
      setState(() {
        _showOverlayIcons = true;
      });
    }

    _overlayHideTimer?.cancel();
    if (!_isOntapsMode) { // ★修正点
      _overlayHideTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _showOverlayIcons = false;
          });
        }
      });
    }
  }

  String _getLevelTooltip() {
    final locale = ui.window.locale.languageCode;
    switch (widget.currentLevel) {
      case Level.level1:
        return locale == 'ja' ? "小学生レベル" : "Elementary Level";
      case Level.level2:
        return locale == 'ja' ? "中学生レベル" : "Junior High Level";
      case Level.level3:
        return locale == 'ja' ? "高校生レベル" : "High School Level";
      case Level.level4:
        return locale == 'ja' ? "大学生レベル" : "University Level";
      case Level.idiom:
        return locale == 'ja' ? "英熟語" : "Idioms";
      case Level.business:
        return locale == 'ja' ? "ビジネス用語" : "Business Terms";
      case Level.review:
        return locale == 'ja' ? "復習リスト" : "Review List";
      case Level.quo:
        return locale == 'ja' ? "世界の偉人たちの名言" : "Famous Quotes";
      default:
        return locale == 'ja' ? "レベル" : "Level";
    }
  }

  String _getDisplayModeTooltip() {
    final locale = ui.window.locale.languageCode;
    if (widget.currentLevel == Level.business) {
      switch (widget.displayModeIndex % 2) {
        case 0:
          return locale == 'ja' ? "用語表示" : "Term Only";
        case 1:
          return locale == 'ja' ? "用語と意味の表示" : "Term & Meaning";
        default:
          return locale == 'ja' ? "表示モード" : "Display Mode";
      }
    } else {
      switch (widget.displayModeIndex % 3) {
        case 0:
          return locale == 'ja' ? "漢字表示" : "Kanji";
        case 1:
          return locale == 'ja' ? "漢字とふりがな表示" : "Kanji & Furigana";
        case 2:
          return locale == 'ja' ? "ふりがなとローマ字表示" : "Furigana & Romaji";
        default:
          return locale == 'ja' ? "表示モード" : "Display Mode";
      }
    }
  }

  String _getSoundTooltip() {
    final locale = ui.window.locale.languageCode;
    if (widget.isMuted) return locale == 'ja' ? "音声なし" : "Muted";
    switch (widget.speechMode) {
      case 1:
        return locale == 'ja' ? "英語音声" : "English Audio";
      case 2:
        return locale == 'ja' ? "日本語音声" : "Japanese Audio";
      case 3:
        return locale == 'ja' ? "英語・日本語音声" : "EN & JA Audio";
      default:
        return locale == 'ja' ? "音声" : "Sound";
    }
  }

  void _showTooltip(BuildContext context, String message) {
    final Orientation orientation = MediaQuery.of(context).orientation;
    if (orientation == Orientation.landscape) {
      return;
    }

    _overlayEntry?.remove();
    _overlayEntry = null;

    _overlayEntry = OverlayEntry(
      builder: (context) => CompositedTransformFollower(
        link: _iconBarLayerLink,
        showWhenUnlinked: false,
        offset: const Offset(0.0, -48.0),
        child: Align(
          alignment: Alignment.topCenter,
          child: Material(
            color: Colors.transparent,
            child: TooltipBubble(text: message),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
    Timer(const Duration(seconds: 2), () {
      _overlayEntry?.remove();
      _overlayEntry = null;
    });
  }

  void _showSwipeTooltip(BuildContext context, String message) {
    _overlayEntry?.remove();
    _overlayEntry = null;

    final EdgeInsets safeAreaPadding = MediaQuery.of(context).padding;

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: safeAreaPadding.top + 20.0,
        left: 0,
        right: 0,
        child: Container(
          alignment: Alignment.center,
          child: Material(
            color: Colors.transparent,
            child: TooltipBubble(text: message),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);

    Timer(const Duration(seconds: 2), () {
      _overlayEntry?.remove();
      _overlayEntry = null;
    });
  }

  Widget _buildBottomControls() {
    final isPortrait =
        MediaQuery.of(context).orientation == Orientation.portrait;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            children: [
              SizedBox(
                width: 100,
                height: 40,
                child: Stack(
                  children: [
                    Visibility(
                      maintainState: true,
                      maintainAnimation: true,
                      maintainSize: true,
                      visible: _isOntapsMode,
                      child: InkWell(
                        onTap: _toggleAutoMode,
                        borderRadius: BorderRadius.circular(20.0),
                        child: Container(
                           decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20.0),
                            border: Border.all(color: _getStyleGradient().colors.first, width: 2),
                          ),
                          child: Center(
                            child: ShaderMask(
                              shaderCallback: (bounds) => _getStyleGradient().createShader(bounds),
                              child: const Text(
                                'Manual',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Visibility(
                      maintainState: true,
                      maintainAnimation: true,
                      maintainSize: true,
                      visible: !_isOntapsMode,
                      child: InkWell(
                        onTap: _toggleAutoMode,
                        borderRadius: BorderRadius.circular(20.0),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20.0),
                            gradient: _getStyleGradient(),
                          ),
                          child: const Center(
                            child: Text(
                              'Auto',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: Colors.white
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 70,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: _isOntapsMode
                        ? Row(
                            key: const ValueKey('arrows'),
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              IconButton(
                                icon: ShaderMask(
                                    shaderCallback: (bounds) =>
                                        _getStyleGradient().createShader(bounds),
                                    blendMode: BlendMode.srcIn,
                                    child: const Icon(Icons.arrow_back_ios,
                                        color: Colors.white)),
                                onPressed: _previousWord,
                              ),
                              IconButton(
                                icon: ShaderMask(
                                  shaderCallback: (bounds) =>
                                      _getStyleGradient().createShader(bounds),
                                  blendMode: BlendMode.srcIn,
                                  child: const Icon(Icons.arrow_forward_ios,
                                      color: Colors.white),
                                ),
                                onPressed: _nextWord,
                              ),
                            ],
                          )
                        : SliderWrapper(
                            key: const ValueKey('slider'),
                            intervalDuration: _currentInterval,
                            getGradient: _getStyleGradient,
                            onIntervalChanged: (newDuration) {
                              widget.onUpdateInterval(newDuration, isPortrait);
                            },
                            maxDurationMs: isPortrait ? 5000 : 10000,
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (widget.currentLevel != Level.review &&
            widget.currentLevel != Level.quo)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: ProgressGauge(
              viewedCount: _viewedCount,
              totalCount: _totalWordsInLevel,
              getGradient: _getStyleGradient,
              onTap: _showResetConfirmationDialog,
            ),
          ),
      ],
    );
  }

  void _toggleAutoMode() {
    setState(() {
      _isOntapsMode = !_isOntapsMode;
      if (_isOntapsMode) {
        _timer?.cancel();
        _overlayHideTimer?.cancel();
        _showOverlayIcons = true;
      } else {
        _startDisplayTimer();
        _resetOverlayIconsVisibility();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final Orientation orientation = MediaQuery.of(context).orientation;
    final bool isPortrait = orientation == Orientation.portrait;
    final double fontSize = isPortrait ? 48 : 64;
    final locale = ui.window.locale.languageCode;

    Widget mainContent;
    if (widget.wordPairs.isEmpty && widget.currentLevel == Level.review) {
      mainContent = Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Text(
            locale == 'ja'
                ? "復習リストは空です。\n単語を横にスワイプして追加できます。"
                : "Review list is empty.\nSwipe words to add them.",
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 18,
                color: Theme.of(context).textTheme.bodyLarge?.color),
          ),
        ),
      );
    } else if (widget.wordPairs.isEmpty) {
      mainContent = Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Text(
            locale == 'ja' ? "このレベルの単語はありません。" : "No words for this level.",
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 18,
                color: Theme.of(context).textTheme.bodyLarge?.color),
          ),
        ),
      );
    } else {
      mainContent = GestureDetector(
        onTap: () {
          _toggleHistoryMode();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: (isPortrait && widget.currentLevel == Level.quo
              ? Text(
                  locale == 'ja'
                      ? "賢者の名言は\n横置きで見てください"
                      : "Please view quotes\nin landscape mode",
                  key: const ValueKey<String>('quote_portrait_message'),
                  style: TextStyle(
                    fontSize: fontSize * 0.5,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Georgia',
                    color: Colors.grey,
                  ),
                  textAlign: TextAlign.center,
                  softWrap: true,
                  maxLines: 3,
                )
              : AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: child,
                    );
                  },
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: ShaderMask(
                      shaderCallback: (bounds) =>
                          _getStyleGradient().createShader(bounds),
                      blendMode: BlendMode.srcIn,
                      child: isPortrait
                          ? (_currentShowEnglish
                              ? FittedBox(
                                  fit: BoxFit.contain,
                                  child: Text(
                                    widget.wordPairs[index]['en']!,
                                    key: ValueKey<String>(
                                        widget.wordPairs[index]['en']!),
                                    style: TextStyle(
                                      fontSize: fontSize,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'Georgia',
                                    ),
                                    textAlign: TextAlign.center,
                                    softWrap: true,
                                    maxLines: 3,
                                  ),
                                )
                              : _buildJapaneseDisplay(
                                  widget.wordPairs[index],
                                  fontSize,
                                  widget.displayModeIndex,
                                  widget.currentLevel))
                          : (widget.currentLevel == Level.quo
                              ? _buildQuoteSentenceExample(
                                  widget.wordPairs[index], _currentShowEnglish)
                              : _buildSentenceExample(widget.wordPairs[index],
                                  _currentShowEnglish)),
                    ),
                  ),
                )),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapDown: (_) => _resetOverlayIconsVisibility(),
          onHorizontalDragEnd: (details) {
            if (details.primaryVelocity!.abs() > 200 &&
                widget.wordPairs.isNotEmpty) {
              HapticFeedback.heavyImpact();
              final currentWord = widget.wordPairs[index];
              final wordId = currentWord['id'] as String;

              if (widget.currentLevel == Level.review) {
                widget.onRemoveReviewWord(wordId);
                _showSwipeTooltip(
                    context,
                    locale == 'ja'
                        ? "復習リストから削除しました"
                        : "Removed from review list");
              } else if (widget.currentLevel != Level.quo) {
                widget.onAddReviewWord(wordId);
                _showSwipeTooltip(
                    context, locale == 'ja' ? "Lv.Reに移動しました" : "Moved to Lv.Re");
              }
            }
          },
          child: Stack(
            alignment: Alignment.center,
            children: [
              Center(
                child: mainContent,
              ),
              AnimatedOpacity(
                opacity: (_isOntapsMode || _showOverlayIcons) ? 1.0 : 0.0, // ★修正点
                duration: const Duration(milliseconds: 300),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 24.0),
                    child: _buildBottomControls(),
                  ),
                ),
              ),
              Builder(
                builder: (context) {
                  final bool isDark =
                      Theme.of(context).brightness == Brightness.dark;
                  final Color bgColor = isDark ? Colors.black : Colors.white;
                  final Color iconColor = isDark ? Colors.white : Colors.black;
                  final bool isLandscape =
                      MediaQuery.of(context).orientation ==
                          Orientation.landscape;
                  final double panelHeight =
                      isLandscape ? MediaQuery.of(context).size.height : 300;
                  return AnimatedBuilder(
                    animation: _historyAnimation,
                    builder: (context, child) {
                      final double top =
                          -panelHeight + _historyAnimation.value * panelHeight;
                      return AnimatedPositioned(
                        duration: const Duration(milliseconds: 0),
                        top: top,
                        left: 0,
                        right: 0,
                        child: Container(
                          height: panelHeight,
                          color: bgColor,
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Visibility(
                                    visible: true,
                                    child: IconButton(
                                      icon: Icon(Icons.close, color: iconColor),
                                      onPressed: () {
                                        HapticFeedback.selectionClick();
                                        _toggleHistoryMode();
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              Expanded(child: _buildHistoryList()),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
              if (!isPortrait)
                Positioned(
                  top: 20,
                  left: 20,
                  child: AnimatedOpacity(
                    opacity: _showOverlayIcons ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 300),
                    child: ShaderMask(
                      shaderCallback: (bounds) =>
                          _getStyleGradient().createShader(bounds),
                      blendMode: BlendMode.srcIn,
                      child: Text(
                        _currentTime,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Georgia',
                        ),
                      ),
                    ),
                  ),
                ),
              AnimatedBuilder(
                animation: _historyAnimation,
                builder: (context, child) {
                  return Visibility(
                    visible: _canShowIcons,
                    child: Positioned(
                        top: isPortrait
                            ? MediaQuery.of(context).padding.top + 60.0
                            : 18.0,
                        right: 0,
                        left: 0,
                        child: AnimatedOpacity(
                          opacity: _showOverlayIcons ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 300),
                          child: CompositedTransformTarget(
                            link: _iconBarLayerLink,
                            child: Center(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    IconButton(
                                      icon: ShaderMask(
                                        shaderCallback: (bounds) =>
                                            _getStyleGradient()
                                                .createShader(bounds),
                                        blendMode: BlendMode.srcIn,
                                        child: const Icon(Icons.star),
                                      ),
                                      onPressed: () async {
                                        _resetOverlayIconsVisibility();
                                        HapticFeedback.selectionClick();
                                        Navigator.of(context).push(
                                          MaterialPageRoute(builder: (_) => const DetailedTutorialScreen()),
                                        );
                                      },
                                    ),
                                    IconButton(
                                      onPressed: () {
                                        _resetOverlayIconsVisibility();
                                        HapticFeedback.selectionClick();
                                        widget.onCycleLevel();
                                        WidgetsBinding.instance
                                            .addPostFrameCallback((_) {
                                          if (mounted)
                                            _showTooltip(
                                                context, _getLevelTooltip());
                                        });
                                      },
                                      icon: ShaderMask(
                                        shaderCallback: (bounds) =>
                                            _getStyleGradient()
                                                .createShader(bounds),
                                        blendMode: BlendMode.srcIn,
                                        child: Text(
                                          getLevelLabel(widget.currentLevel),
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            fontFamily: 'Georgia',
                                          ),
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: () {
                                        _resetOverlayIconsVisibility();
                                        HapticFeedback.selectionClick();
                                        widget.onToggleLanguageOrder();
                                        WidgetsBinding.instance
                                            .addPostFrameCallback((_) {
                                          if (mounted)
                                            _showTooltip(
                                                context,
                                                widget.showEnglishFirst
                                                    ? (locale == 'ja'
                                                        ? '表示順序: 日本語→英語'
                                                        : 'Order: JA→EN')
                                                    : (locale == 'ja'
                                                        ? '表示順序: 英語→日本語'
                                                        : 'Order: EN→JA'));
                                        });
                                      },
                                      icon: ShaderMask(
                                        shaderCallback: (Rect bounds) {
                                          return _getStyleGradient()
                                              .createShader(bounds);
                                        },
                                        blendMode: BlendMode.srcIn,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 2, vertical: 1),
                                          child: Text(
                                            widget.showEnglishFirst
                                                ? 'A→あ'
                                                : 'あ→A',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 15,
                                              fontFamily: 'Georgia',
                                              letterSpacing: 0,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: () {
                                        _resetOverlayIconsVisibility();
                                        HapticFeedback.selectionClick();
                                        widget.onCycleDisplayMode();
                                        WidgetsBinding.instance
                                            .addPostFrameCallback((_) {
                                          if (mounted)
                                            _showTooltip(context,
                                                _getDisplayModeTooltip());
                                        });
                                      },
                                      icon: ShaderMask(
                                        shaderCallback: (bounds) =>
                                            _getStyleGradient()
                                                .createShader(bounds),
                                        blendMode: BlendMode.srcIn,
                                        child: Text(
                                          widget.currentLevel == Level.business
                                              ? [
                                                  '漢',
                                                  '漢あ'
                                                ][widget.displayModeIndex % 2]
                                              : [
                                                  '漢',
                                                  '漢あ',
                                                  'あA'
                                                ][widget.displayModeIndex % 3],
                                          softWrap: false,
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            fontFamily: 'Georgia',
                                          ),
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      icon: ShaderMask(
                                        shaderCallback: (bounds) =>
                                            _getStyleGradient()
                                                .createShader(bounds),
                                        blendMode: BlendMode.srcIn,
                                        child: widget.isMuted
                                            ? const Icon(Icons.volume_off)
                                            : Text(
                                                (widget.speechMode >= 1 &&
                                                        widget.speechMode <= 3)
                                                    ? [
                                                        'EN',
                                                        'JP',
                                                        'ENJP'
                                                      ][widget.speechMode - 1]
                                                    : '',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13,
                                                ),
                                              ),
                                      ),
                                      onPressed: () {
                                        _resetOverlayIconsVisibility();
                                        HapticFeedback.selectionClick();
                                        widget.onUpdateSpeechMode();
                                        WidgetsBinding.instance
                                            .addPostFrameCallback((_) {
                                          if (mounted)
                                            _showTooltip(
                                                context, _getSoundTooltip());
                                        });
                                      },
                                    ),
                                    IconButton(
                                      onPressed: () {
                                        _resetOverlayIconsVisibility();
                                        HapticFeedback.selectionClick();
                                        widget.onCycleGradientIndex();
                                        _showTooltip(
                                            context,
                                            locale == 'ja'
                                                ? "色を変更しました"
                                                : "Color Changed");
                                      },
                                      icon: ShaderMask(
                                        shaderCallback: (bounds) =>
                                            _getStyleGradient()
                                                .createShader(bounds),
                                        blendMode: BlendMode.srcIn,
                                        child: const Icon(Icons.color_lens),
                                      ),
                                    ),
                                    IconButton(
                                      icon: ShaderMask(
                                        shaderCallback: (bounds) =>
                                            _getStyleGradient()
                                                .createShader(bounds),
                                        blendMode: BlendMode.srcIn,
                                        child: const Icon(Icons.brightness_6),
                                      ),
                                      onPressed: () {
                                        _resetOverlayIconsVisibility();
                                        HapticFeedback.selectionClick();
                                        widget.onToggleTheme();
                                        WidgetsBinding.instance
                                            .addPostFrameCallback((_) {
                                          if (mounted) {
                                            _showTooltip(
                                                context,
                                                Theme.of(context)
                                                            .brightness !=
                                                        Brightness.dark
                                                    ? (locale == 'ja'
                                                        ? 'ダークモードに切り替え'
                                                        : 'Switch to Dark Mode')
                                                    : (locale == 'ja'
                                                        ? 'ライトモードに切り替え'
                                                        : 'Switch to Light Mode'));
                                          }
                                        });
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        )),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSentenceExample(Map<String, dynamic> word, bool showEnglish) {
    final sentenceEn = word['sentence_en'] ?? '';
    final sentenceJa = word['sentence_ja'] ?? '';
    final target = word['en'] ?? '';
    final targetJa = word['kanji'] ?? '';

    if (showEnglish) {
      if (sentenceEn.isEmpty ||
          target.isEmpty ||
          !sentenceEn.contains(target)) {
        return Text(
          sentenceEn,
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.normal,
            fontFamily: 'Georgia',
          ),
          textAlign: TextAlign.center,
        );
      }

      final parts = sentenceEn.split(target);
      return Text.rich(
        TextSpan(
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.normal,
            fontFamily: 'Georgia',
          ),
          children: [
            TextSpan(text: parts[0]),
            TextSpan(
              text: target,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            TextSpan(text: parts.sublist(1).join(target)),
          ],
        ),
        textAlign: TextAlign.center,
      );
    } else {
      if (sentenceJa.isEmpty ||
          targetJa.isEmpty ||
          !sentenceJa.contains(targetJa)) {
        return Text(
          sentenceJa,
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.normal,
            fontFamily: 'Georgia',
          ),
          textAlign: TextAlign.center,
        );
      }

      final parts = sentenceJa.split(targetJa);
      return Text.rich(
        TextSpan(
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.normal,
            fontFamily: 'Georgia',
          ),
          children: [
            TextSpan(text: parts[0]),
            TextSpan(
              text: targetJa,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            TextSpan(text: parts.sublist(1).join(targetJa)),
          ],
        ),
        textAlign: TextAlign.center,
      );
    }
  }

  Widget _buildQuoteSentenceExample(
      Map<String, dynamic> word, bool showEnglish) {
    final sentenceEn = word['sentence_en'] ?? '';
    final sentenceJa = word['sentence_ja'] ?? '';

    String text = showEnglish ? sentenceEn : sentenceJa;
    final RegExp authorReg =
        RegExp(r'(.*?)([\s\u3000]*[-–ー][\s\u3000]*[^\n]+)$');
    final match = authorReg.firstMatch(text);
    if (match != null) {
      text = '${match.group(1)}\n${match.group(2)}';
    }
    return Text(
      text,
      style: const TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.normal,
        fontFamily: 'Georgia',
      ),
      textAlign: TextAlign.center,
    );
  }

  String getLevelLabel(dynamic level) {
    switch (level) {
      case Level.level1:
        return 'Lv.1';
      case Level.level2:
        return 'Lv.2';
      case Level.level3:
        return 'Lv.3';
      case Level.level4:
        return 'Lv.4';
      case Level.idiom:
        return 'Lv.Id';
      case Level.business:
        return 'Lv.Bz';
      case Level.review:
        return 'Lv.Re';
      case Level.quo:
        return 'Lv.Q';
      default:
        return '';
    }
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  double _speed = 1.0;
  String _difficulty = 'Easy';

  final List<String> _difficulties = ['Easy', 'Medium', 'Hard'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text('Difficulty', style: Theme.of(context).textTheme.titleMedium),
            DropdownButton<String>(
              value: _difficulty,
              items: _difficulties.map((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value),
                );
              }).toList(),
              onChanged: (newValue) {
                setState(() {
                  _difficulty = newValue!;
                });
              },
            ),
          ],
        ),
      ),
    );
  }
}

Widget _buildJapaneseDisplay(Map<String, dynamic> word, double fontSize,
    int displayModeIndex, Level currentLevel) {
  if (currentLevel == Level.business) {
    String kanjiText = (word['kanji'] ?? '').replaceAll('（', '\n（');
    switch (displayModeIndex % 2) {
      case 0:
        return FittedBox(
          fit: BoxFit.contain,
          child: Text(
            kanjiText,
            key: const ValueKey('business_kanji'),
            style: TextStyle(
              fontSize: fontSize * 0.8,
              fontWeight: FontWeight.bold,
              fontFamily: 'Georgia',
            ),
            textAlign: TextAlign.center,
          ),
        );
      case 1:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            FittedBox(
              fit: BoxFit.contain,
              child: Text(
                kanjiText,
                key: const ValueKey('business_kanji_meaning_kanji'),
                style: TextStyle(
                  fontSize: fontSize * 0.8,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Georgia',
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Text(
                word['meaning'] ?? '',
                key: const ValueKey('business_kanji_meaning_meaning'),
                style: TextStyle(
                  fontSize: fontSize * 0.4,
                  fontWeight: FontWeight.normal,
                  fontFamily: 'Georgia',
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  } else {
    switch (displayModeIndex % 3) {
      case 0:
        return FittedBox(
          fit: BoxFit.contain,
          child: Text(
            word['kanji'] ?? '',
            key: const ValueKey('kanji'),
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.bold,
              fontFamily: 'Georgia',
            ),
            textAlign: TextAlign.center,
          ),
        );
      case 1:
        return FittedBox(
          fit: BoxFit.contain,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                word['kanji'] ?? '',
                key: const ValueKey('kanji_plus_hiragana_kanji'),
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Georgia',
                ),
                textAlign: TextAlign.center,
              ),
              Text(
                word['hiragana'] ?? '',
                key: const ValueKey('kanji_plus_hiragana_hiragana'),
                style: TextStyle(
                  fontSize: fontSize * 0.6,
                  fontWeight: FontWeight.normal,
                  fontFamily: 'Georgia',
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      case 2:
        return FittedBox(
          fit: BoxFit.contain,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                word['hiragana'] ?? '',
                key: const ValueKey('hiragana_plus_romaji_hiragana'),
                style: TextStyle(
                  fontSize: fontSize * 0.9,
                  fontWeight: FontWeight.normal,
                  fontFamily: 'Georgia',
                ),
                textAlign: TextAlign.center,
              ),
              Text(
                word['romaji'] ?? '',
                key: const ValueKey('hiragana_plus_romaji_romaji'),
                style: TextStyle(
                  fontSize: fontSize * 0.8,
                  fontWeight: FontWeight.normal,
                  fontFamily: 'Georgia',
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

class SliderWrapper extends StatefulWidget {
  final Duration intervalDuration;
  final ValueChanged<Duration> onIntervalChanged;
  final LinearGradient Function() getGradient;
  final int maxDurationMs;

  const SliderWrapper({
    super.key,
    required this.intervalDuration,
    required this.onIntervalChanged,
    required this.getGradient,
    this.maxDurationMs = 3000,
  });

  @override
  State<SliderWrapper> createState() => _SliderWrapperState();
}

class _SliderWrapperState extends State<SliderWrapper> {
  double _sliderValue = 0.0;

  double _durationToSliderValue(Duration duration) {
    final ms = duration.inMilliseconds;
    final maxMs = widget.maxDurationMs;
    return ((maxMs - ms) / (maxMs - 500)).clamp(0.0, 1.0);
  }

  @override
  void initState() {
    super.initState();
    _sliderValue = _durationToSliderValue(widget.intervalDuration);
  }

  @override
  void didUpdateWidget(covariant SliderWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.intervalDuration != widget.intervalDuration ||
        oldWidget.maxDurationMs != widget.maxDurationMs) {
      if (mounted) {
        setState(() {
          _sliderValue = _durationToSliderValue(widget.intervalDuration);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxMs = widget.maxDurationMs;
    final _currentInterval = Duration(
      milliseconds: (maxMs - _sliderValue * (maxMs - 500)).round(),
    );
    return ShaderMask(
      shaderCallback: (bounds) => widget
          .getGradient()
          .createShader(Rect.fromLTWH(0, 0, bounds.width, bounds.height)),
      blendMode: BlendMode.srcIn,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '${(_currentInterval.inMilliseconds / 1000).toStringAsFixed(1)}s',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4.0,
              thumbShape: RoundSliderThumbShape(enabledThumbRadius: 8.0),
              overlayShape: RoundSliderOverlayShape(overlayRadius: 12.0),
            ),
            child: Slider(
              value: _sliderValue,
              min: 0.0,
              max: 1.0,
              divisions: 100,
              onChanged: (value) {
                Duration newDuration = Duration(
                  milliseconds: (maxMs - value * (maxMs - 500)).round(),
                );
                widget.onIntervalChanged(newDuration);
                setState(() {
                  _sliderValue = value;
                });
              },
            ),
          ),
        ],
      ),
    );
  }
}

class ProgressGauge extends StatelessWidget {
  final int viewedCount;
  final int totalCount;
  final LinearGradient Function() getGradient;
  final VoidCallback? onTap;

  const ProgressGauge({
    super.key,
    required this.viewedCount,
    required this.totalCount,
    required this.getGradient,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    double progress = totalCount > 0 ? viewedCount / totalCount : 0.0;
    progress = progress.clamp(0.0, 1.0);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: ShaderMask(
        shaderCallback: (bounds) => getGradient().createShader(bounds),
        blendMode: BlendMode.srcIn,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$viewedCount / $totalCount',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              height: 8,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: Colors.white.withOpacity(0.3),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: progress,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TooltipBubble extends StatelessWidget {
  final String text;
  const TooltipBubble({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        textAlign: TextAlign.center,
        softWrap: false,
      ),
    );
  }
}

class TutorialOverlay extends StatelessWidget {
  final VoidCallback onFinished;

  const TutorialOverlay({super.key, required this.onFinished});

  @override
  Widget build(BuildContext context) {
    final locale = ui.window.locale.languageCode;
    final bool isJapanese = locale == 'ja';

    return Material(
      color: Colors.black.withOpacity(0.8),
      child: Stack(
        children: [
          _TutorialInfoBox(
            text: isJapanese
                ? '左右にスワイプして\n「復習リスト」に追加'
                : 'Swipe left or right\nto add to "Review List"',
            top: MediaQuery.of(context).size.height * 0.5 - 100,
            alignment: Alignment.center,
            icon: Icons.swap_horiz,
          ),
          _TutorialInfoBox(
            text: isJapanese ? 'タップで単語の\n「履歴」を表示' : 'Tap to show\nword "History"',
            top: MediaQuery.of(context).size.height * 0.5 + 40,
            alignment: Alignment.center,
          ),
          _TutorialInfoBox(
            text: isJapanese ? '各種設定アイコン' : 'Settings Icons',
            top: MediaQuery.of(context).padding.top + 100,
            alignment: Alignment.center,
            icon: Icons.arrow_upward,
          ),
          _TutorialInfoBox(
            text:
                isJapanese ? 'タップで速度と進捗を表示' : 'Tap to show speed & progress',
            bottom: 120,
            alignment: Alignment.center,
            icon: Icons.arrow_upward,
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 50.0),
              child: ElevatedButton(
                onPressed: onFinished,
                style: ElevatedButton.styleFrom(
                  foregroundColor: Colors.black,
                  backgroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                  textStyle: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
                child: Text(isJapanese ? 'はじめる' : 'Get Started'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TutorialInfoBox extends StatelessWidget {
  final String text;
  final double? top;
  final double? bottom;
  final Alignment alignment;
  final IconData? icon;

  const _TutorialInfoBox({
    required this.text,
    this.top,
    this.bottom,
    required this.alignment,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: top,
      bottom: bottom,
      left: 0,
      right: 0,
      child: Container(
        alignment: alignment,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null && (bottom == null || top != null))
              Icon(icon, color: Colors.white, size: 40),
            if (icon != null && (bottom == null || top != null))
              const SizedBox(height: 8),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                height: 1.5,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (icon != null && bottom != null) const SizedBox(height: 8),
            if (icon != null && bottom != null)
              Icon(icon, color: Colors.white, size: 40),
          ],
        ),
      ),
    );
  }
}

// --- 詳細チュートリアル画面 ---
class DetailedTutorialScreen extends StatelessWidget {
  const DetailedTutorialScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isJapanese = ui.window.locale.languageCode == 'ja';
    return Scaffold(
      appBar: AppBar(
        title: Text(isJapanese ? '詳細チュートリアル' : 'Detailed Tutorial'),
        backgroundColor: Colors.green.shade400,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              isJapanese ? '【縦置き（ポートレート）モードの使い方】' : 'Portrait Mode Usage',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              isJapanese
                  ? '・単語が大きく中央に表示されます。\n・左右にスワイプして「復習リスト（Lv.Re）」に追加できます。\n・上部のアイコンバーで「レベル切替」「表示順切替」「音声切替」などができます。\n・進捗ゲージや速度調整スライダーも活用しましょう。\n・漢字、ひらがな、ローマ字も表示されるので、漢字が読めないお子様や日本語学習者にも最適です。\n・Auto（自動送り）とManual（手動送り）モードを切り替えて学習スタイルに合わせられます。\n・Lv.Bz（ビジネスモード）では「漢あ」モードにすると意味も表示されます。\n・Lv.Re（復習モード）では覚えた単語は再び横スワイプでリストから削除できます。'
                  : '・Words are displayed large and centered.\n・Swipe left/right to add to the "Review List" (displayed as Lv.Re).\n・Use the top icon bar for level switching, display order, and sound settings.\n・Progress gauge and speed slider are also available.\n・Kanji, hiragana, and romaji are shown, making it ideal for children who cannot read kanji or for Japanese learners.\n・You can switch between Auto (auto-advance) and Manual (manual) modes to match your learning style.\n・In Lv.Bz (Business mode), if you select the "漢あ" mode, the meaning will also be displayed.\n・In Lv.Re (Review mode), you can remove learned words from the list again by swiping horizontally.',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 32),
            Text(
              isJapanese ? '【横置き（ランドスケープ）モードの使い方】' : 'Landscape Mode Usage',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              isJapanese
                  ? '・単語や例文が大きく表示されます。\n・音声再生や自動送りモードが使えます。\n・画面下部の操作パネルで各種設定が可能です。'
                  : '・Words and example sentences are displayed large.\n・Audio playback and auto-advance mode are available.\n・Use the bottom control panel for various settings.',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 32),
            Text(
              isJapanese ? '【その他の便利な機能】' : 'Other Useful Features',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              isJapanese
                  ? '・星アイコンからこの詳細チュートリアルにいつでもアクセスできます。\n・「A→あ」や「EN/JP」などのアイコンで表示順や音声を切り替えられます。\n・進捗ゲージをタップすると学習進捗をリセットできます。'
                  : '・Access this detailed tutorial anytime from the star icon.\n・Switch display order and audio with icons like "A→あ" or "EN/JP".\n・Tap the progress gauge to reset your learning progress.',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 32),
            Center(
              child: ElevatedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back),
                label: Text(isJapanese ? 'もどる' : 'Back'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade400,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                  textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
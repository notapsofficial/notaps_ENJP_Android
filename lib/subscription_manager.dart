import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';

class SubscriptionManager {
  static const String subscriptionId = 'notaps_monthly_subscription';
  // テスト用の商品ID（Google Play Consoleで設定する必要があります）
  // テスト用：30秒で5日後、さらに30秒で7日後をシミュレート
  static const int _freeTrialSeconds = 60 * 60 * 24 * 3; // 3日間（259200秒）で無料体験終了
  static const int _shareBonusSeconds = 30; // 30秒でシェア延長終了
  static const String annualSubscriptionId = 'notaps_annual_subscription'; // 年額プランID
  static const List<String> _testProductIds = [
    'notaps_monthly_subscription',
    'notaps_annual_subscription',
    'android.test.purchased',
  ];
  
  static final SubscriptionManager _instance = SubscriptionManager._internal();
  factory SubscriptionManager() => _instance;
  SubscriptionManager._internal();

  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  List<ProductDetails> _products = [];
  bool _isAvailable = false;
  bool _purchasePending = false;

  // サブスクリプション状態
  bool _isSubscribed = false;
  DateTime? _trialEndDate;
  DateTime? _subscriptionEndDate;
  bool _hasShared = false;

  // Getters
  bool get isSubscribed => _isSubscribed;
  bool get isAvailable => _isAvailable;
  bool get purchasePending => _purchasePending;
  List<ProductDetails> get products => _products;
  List<ProductDetails> get annualProducts => _products.where((p) => p.id == annualSubscriptionId).toList();
  List<ProductDetails> get monthlyProducts => _products.where((p) => p.id == subscriptionId).toList();
  
  DateTime? get trialEndDate => _trialEndDate;
  DateTime? get subscriptionEndDate => _subscriptionEndDate;
  bool get hasShared => _hasShared;

  // 無料期間が残っているかチェック
  bool get hasFreeTrialRemaining {
    if (_isSubscribed) return false;
    if (_trialEndDate == null) return true;
    return DateTime.now().isBefore(_trialEndDate!);
  }

  // 無料期間の残り日数を取得
  int get remainingFreeDays {
    if (_isSubscribed || _trialEndDate == null) return 0;
    final remaining = _trialEndDate!.difference(DateTime.now()).inDays;
    return remaining > 0 ? remaining : 0;
  }

  // 初期化
  Future<void> initialize() async {
    await _loadSubscriptionStatus();
    
    _isAvailable = await _inAppPurchase.isAvailable();
    if (!_isAvailable) return;

    // 商品情報を取得
    final ProductDetailsResponse response = await _inAppPurchase.queryProductDetails({..._testProductIds});
    if (response.notFoundIDs.isNotEmpty) {
      print('Products not found: ${response.notFoundIDs}');
      // テスト用: 商品が見つからない場合でも続行
    }
    _products = response.productDetails;

    // 購入状態の監視
    _subscription = _inAppPurchase.purchaseStream.listen(
      _onPurchaseUpdate,
      onDone: () => _subscription?.cancel(),
      onError: (error) => print('Purchase stream error: $error'),
    );
  }

  // 購入状態の更新処理
  Future<void> _onPurchaseUpdate(List<PurchaseDetails> purchaseDetailsList) async {
    for (final PurchaseDetails purchaseDetails in purchaseDetailsList) {
      if (purchaseDetails.status == PurchaseStatus.pending) {
        _purchasePending = true;
      } else {
        _purchasePending = false;
        if (purchaseDetails.status == PurchaseStatus.purchased ||
            purchaseDetails.status == PurchaseStatus.restored) {
          await _verifyPurchase(purchaseDetails);
        }
        if (purchaseDetails.pendingCompletePurchase) {
          await _inAppPurchase.completePurchase(purchaseDetails);
        }
      }
    }
  }

  // 購入の検証
  Future<void> _verifyPurchase(PurchaseDetails purchaseDetails) async {
    if (purchaseDetails.productID == subscriptionId) {
      await _setSubscriptionStatus(true);
      await _setSubscriptionEndDate(DateTime.now().add(Duration(days: 30)));
    }
  }

  // サブスクリプション開始（プランID指定）
  Future<bool> startSubscription({String? productId}) async {
    if (!_isAvailable || _products.isEmpty) return false;
    final id = productId ?? subscriptionId;
    final product = _products.firstWhere((p) => p.id == id, orElse: () => _products.first);
    final PurchaseParam purchaseParam = PurchaseParam(productDetails: product);
    return await _inAppPurchase.buyNonConsumable(purchaseParam: purchaseParam);
  }

  // サブスクリプション復元
  Future<void> restorePurchases() async {
    await _inAppPurchase.restorePurchases();
  }

  // 無料期間の開始
  Future<void> startFreeTrial() async {
    if (_trialEndDate != null) return; // 既に開始済み
    final prefs = await SharedPreferences.getInstance();
    final trialStartDate = DateTime.now();
    final trialEndDate = trialStartDate.add(Duration(seconds: _freeTrialSeconds));
    await prefs.setString('trial_start_date', trialStartDate.toIso8601String());
    await prefs.setString('trial_end_date', trialEndDate.toIso8601String());
    _trialEndDate = trialEndDate;
  }

  // SNSシェアで無料期間を延長
  Future<void> extendTrialBySharing() async {
    if (_hasShared) return; // 既にシェア済み
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_shared', true);
    _hasShared = true;
    if (_trialEndDate != null) {
      final newEndDate = _trialEndDate!.add(Duration(seconds: _shareBonusSeconds));
      await prefs.setString('trial_end_date', newEndDate.toIso8601String());
      _trialEndDate = newEndDate;
    }
  }

  // SNSシェアの実行
  Future<void> shareToSocialMedia() async {
    const url = 'https://play.google.com/store/apps/details?id=com.notaps.study.enjp.corporate';
    const text = 'notaps - 英語学習アプリで効率的に単語を覚えよう！';
    
    // テスト用: 複数のSNSプラットフォームに対応
    final twitterUrl = 'https://twitter.com/intent/tweet?text=${Uri.encodeComponent(text)}&url=${Uri.encodeComponent(url)}';
    final facebookUrl = 'https://www.facebook.com/sharer/sharer.php?u=${Uri.encodeComponent(url)}';
    final lineUrl = 'https://social-plugins.line.me/lineit/share?url=${Uri.encodeComponent(url)}';
    
    // テスト用: 最初にTwitterを試す
    if (await canLaunchUrl(Uri.parse(twitterUrl))) {
      await launchUrl(Uri.parse(twitterUrl));
      await extendTrialBySharing();
    } else if (await canLaunchUrl(Uri.parse(facebookUrl))) {
      await launchUrl(Uri.parse(facebookUrl));
      await extendTrialBySharing();
    } else if (await canLaunchUrl(Uri.parse(lineUrl))) {
      await launchUrl(Uri.parse(lineUrl));
      await extendTrialBySharing();
    }
  }

  // サブスクリプション状態の保存
  Future<void> _setSubscriptionStatus(bool isSubscribed) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_subscribed', isSubscribed);
    _isSubscribed = isSubscribed;
  }

  // サブスクリプション終了日の保存
  Future<void> _setSubscriptionEndDate(DateTime endDate) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('subscription_end_date', endDate.toIso8601String());
    _subscriptionEndDate = endDate;
  }

  // サブスクリプション状態の読み込み
  Future<void> _loadSubscriptionStatus() async {
    final prefs = await SharedPreferences.getInstance();
    
    _isSubscribed = prefs.getBool('is_subscribed') ?? false;
    _hasShared = prefs.getBool('has_shared') ?? false;
    
    final trialEndDateStr = prefs.getString('trial_end_date');
    if (trialEndDateStr != null) {
      _trialEndDate = DateTime.parse(trialEndDateStr);
    }
    
    final subscriptionEndDateStr = prefs.getString('subscription_end_date');
    if (subscriptionEndDateStr != null) {
      _subscriptionEndDate = DateTime.parse(subscriptionEndDateStr);
    }

    // 初回起動時は無料期間を開始
    if (_trialEndDate == null && !_isSubscribed) {
      await startFreeTrial();
    }
  }

  // アプリの使用可否をチェック
  bool canUseApp() {
    if (_isSubscribed) return true;
    if (hasFreeTrialRemaining) return true;
    return false;
  }

  // リソースの解放
  void dispose() {
    _subscription?.cancel();
  }
} 
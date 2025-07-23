import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui' as ui;
import 'subscription_manager.dart';

class SubscriptionScreen extends StatefulWidget {
  final VoidCallback onSubscriptionComplete;

  const SubscriptionScreen({
    super.key,
    required this.onSubscriptionComplete,
  });

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  final SubscriptionManager _subscriptionManager = SubscriptionManager();
  bool _isLoading = false;
  int _selectedPlan = 0; // 0: 月額, 1: 年額
  // テスト用：UI強制切り替え用の状態
  int _testUiState = 0; // 0:最初, 1:5日目, 2:7日目

  @override
  void initState() {
    super.initState();
    _initializeSubscription();
  }

  Future<void> _initializeSubscription() async {
    setState(() => _isLoading = true);
    await _subscriptionManager.initialize();
    setState(() => _isLoading = false);
  }

  LinearGradient _getStyleGradient() {
    return LinearGradient(
      colors: [
        Color(0xFF2ECC71),
        Color(0xFF58D68D),
        Color(0xFF48C9B0),
        Color(0xFF5DADE2)
      ],
      stops: [0.0, 0.3, 0.6, 1.0],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  }

  @override
  Widget build(BuildContext context) {
    final locale = ui.window.locale.languageCode;
    final bool isJapanese = locale == 'ja';

    final monthly = _subscriptionManager.monthlyProducts.isNotEmpty ? _subscriptionManager.monthlyProducts.first : null;
    final annual = _subscriptionManager.annualProducts.isNotEmpty ? _subscriptionManager.annualProducts.first : null;
    final monthlyPrice = monthly?.price ?? (isJapanese ? '¥100/月' : '¥100/mo');
    final annualPrice = annual?.price ?? (isJapanese ? '¥800/年' : '¥800/yr');
    final annualPromo = isJapanese ? '4ヶ月分お得！' : '4 months free!';

    List<Widget> children = [];
    if (_subscriptionManager.hasFreeTrialRemaining) {
      children.add(_buildFreeTrialCard(isJapanese, _subscriptionManager.remainingFreeDays));
      children.add(const SizedBox(height: 24)); // カードとボタンの間に余白を追加
      children.add(
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {
              widget.onSubscriptionComplete();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _getStyleGradient().colors.first,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              isJapanese ? '無料期間で使用開始' : 'Start with Free Trial',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      );
    }
    if (!_subscriptionManager.hasFreeTrialRemaining) {
      children.add(
        Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ChoiceChip(
                  label: Text(isJapanese ? '月額' : 'Monthly'),
                  selected: _selectedPlan == 0,
                  onSelected: (_) => setState(() => _selectedPlan = 0),
                ),
                const SizedBox(width: 12),
                ChoiceChip(
                  label: Row(
                    children: [
                      Text(isJapanese ? '年額' : 'Annual'),
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(annualPromo, style: const TextStyle(color: Colors.white, fontSize: 10)),
                      ),
                    ],
                  ),
                  selected: _selectedPlan == 1,
                  onSelected: (_) => setState(() => _selectedPlan = 1),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  setState(() => _isLoading = true);
                  final planId = _selectedPlan == 0 ? SubscriptionManager.subscriptionId : SubscriptionManager.annualSubscriptionId;
                  final success = await _subscriptionManager.startSubscription(productId: planId);
                  setState(() => _isLoading = false);
                  if (success) {
                    widget.onSubscriptionComplete();
                  } else {
                    _showErrorDialog(isJapanese);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _getStyleGradient().colors.first,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(_selectedPlan == 0 ? (isJapanese ? '毎月100円で継続（$monthlyPrice）' : 'Continue for $monthlyPrice') : (isJapanese ? '年額800円で継続（$annualPrice）' : 'Continue for $annualPrice'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      );
    }
    // 画面崩れ防止のため、Scaffold > SafeArea > SingleChildScrollView > Padding > Columnでラップ
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Container(
            height: MediaQuery.of(context).size.height -
                MediaQuery.of(context).padding.top -
                MediaQuery.of(context).padding.bottom,
          child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFreeTrialCard(bool isJapanese, int remainingDays) {
    return Center(
      child: Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: _getStyleGradient(),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
          mainAxisSize: MainAxisSize.min,
        children: [
            Icon(Icons.free_breakfast, color: Colors.white, size: 48),
          const SizedBox(height: 16),
          Text(
              isJapanese ? '全機能無料体験中！' : 'All Features Free!',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isJapanese 
                  ? '今だけ3日間無料で使えます！'
                  : 'Enjoy all features free for 3 days!',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
            ),
              textAlign: TextAlign.center,
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildSubscriptionCard(bool isJapanese) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        children: [
          Icon(
            Icons.star,
            color: Colors.amber.shade600,
            size: 48,
          ),
          const SizedBox(height: 16),
          Text(
            isJapanese ? 'プレミアムサブスクリプション' : 'Premium Subscription',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isJapanese ? '月額100円で全ての機能を利用' : '¥100/month for all features',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey.shade600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildFeatureItem(Icons.check, isJapanese ? '全てのレベル' : 'All Levels'),
              _buildFeatureItem(Icons.check, isJapanese ? '無制限使用' : 'Unlimited Use'),
              _buildFeatureItem(Icons.check, isJapanese ? '広告なし' : 'No Ads'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureItem(IconData icon, String text) {
    return Column(
      children: [
        Icon(icon, color: Colors.green.shade600, size: 24),
        const SizedBox(height: 4),
        Text(
          text,
          style: TextStyle(fontSize: 12),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildFifthDayCard(bool isJapanese) {
    // 年額バッジ文言
    final annualPromo = isJapanese ? '4ヶ月分お得！' : '4 months free!';
    final monthly = _subscriptionManager.monthlyProducts.isNotEmpty ? _subscriptionManager.monthlyProducts.first : null;
    final annual = _subscriptionManager.annualProducts.isNotEmpty ? _subscriptionManager.annualProducts.first : null;
    final monthlyPrice = monthly?.price ?? (isJapanese ? '¥100/月' : '¥100/mo');
    final annualPrice = annual?.price ?? (isJapanese ? '¥800/年' : '¥800/yr');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 24),
        // 無料期間終了 赤枠
        Container(
          padding: const EdgeInsets.all(16),
          margin: const EdgeInsets.only(bottom: 24),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            border: Border.all(color: Colors.red, width: 2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            isJapanese ? '無料期間終了' : 'Free Trial Ended',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.red.shade700),
            textAlign: TextAlign.center,
          ),
        ),
        // プラン選択チップ
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ChoiceChip(
              label: Text(isJapanese ? '月額' : 'Monthly'),
              selected: _selectedPlan == 0,
              onSelected: (_) => setState(() => _selectedPlan = 0),
            ),
            const SizedBox(width: 12),
            ChoiceChip(
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(isJapanese ? '年額' : 'Annual'),
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      annualPromo,
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ),
                ],
              ),
              selected: _selectedPlan == 1,
              onSelected: (_) => setState(() => _selectedPlan = 1),
            ),
          ],
        ),
        const SizedBox(height: 24),
        // サブスク課金ボタンのみ
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
            onPressed: () async {
              setState(() => _isLoading = true);
              final planId = _selectedPlan == 0 ? SubscriptionManager.subscriptionId : SubscriptionManager.annualSubscriptionId;
              final success = await _subscriptionManager.startSubscription(productId: planId);
              setState(() => _isLoading = false);
              if (success) {
                widget.onSubscriptionComplete();
              } else {
                _showErrorDialog(isJapanese);
              }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _getStyleGradient().colors.first,
                foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 20),
              textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            child: Text(_selectedPlan == 0 ? (isJapanese ? '毎月100円で継続（$monthlyPrice）' : 'Continue for $monthlyPrice') : (isJapanese ? '年額800円で継続（$annualPrice）' : 'Continue for $annualPrice')),
          ),
        ),
      ],
    );
  }

  Widget _buildSeventhDayCard(bool isJapanese) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: _getStyleGradient(),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(Icons.star, color: Colors.white, size: 48),
          const SizedBox(height: 16),
          Text(
            isJapanese ? '無料期間が完全に終了しました' : 'Free Period Ended',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
              ),
          const SizedBox(height: 8),
          Text(
            isJapanese
                ? '毎月100円で継続できるよ！'
                : 'You can continue for just ¥100/month!',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(bool isJapanese, {bool isSeventhDay = false}) {
    if (isSeventhDay) {
      final monthly = _subscriptionManager.monthlyProducts.isNotEmpty ? _subscriptionManager.monthlyProducts.first : null;
      final annual = _subscriptionManager.annualProducts.isNotEmpty ? _subscriptionManager.annualProducts.first : null;
      final monthlyPrice = monthly?.price ?? (isJapanese ? '¥100/月' : '¥100/mo');
      final annualPrice = annual?.price ?? (isJapanese ? '¥800/年' : '¥800/yr');
      final annualPromo = isJapanese ? '4ヶ月分お得！' : '4 months free!';
      return Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ChoiceChip(
                label: Text(isJapanese ? '月額' : 'Monthly'),
                selected: _selectedPlan == 0,
                onSelected: (_) => setState(() => _selectedPlan = 0),
              ),
              const SizedBox(width: 12),
              ChoiceChip(
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(isJapanese ? '年額' : 'Annual'),
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(annualPromo, style: const TextStyle(color: Colors.white, fontSize: 10)),
                    ),
                  ],
                ),
                selected: _selectedPlan == 1,
                onSelected: (_) => setState(() => _selectedPlan = 1),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () async {
                setState(() => _isLoading = true);
                final planId = _selectedPlan == 0 ? SubscriptionManager.subscriptionId : SubscriptionManager.annualSubscriptionId;
                final success = await _subscriptionManager.startSubscription(productId: planId);
                setState(() => _isLoading = false);
                if (success) {
                  widget.onSubscriptionComplete();
                } else {
                  _showErrorDialog(isJapanese);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _getStyleGradient().colors.first,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 20),
                textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(_selectedPlan == 0 ? (isJapanese ? '毎月100円で継続（$monthlyPrice）' : 'Continue for $monthlyPrice') : (isJapanese ? '年額800円で継続（$annualPrice）' : 'Continue for $annualPrice'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
    }
    return const SizedBox.shrink();
  }

  void _showErrorDialog(bool isJapanese) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isJapanese ? 'エラー' : 'Error'),
        content: Text(
          isJapanese 
              ? 'サブスクリプションの開始に失敗しました。\n後でもう一度お試しください。'
              : 'Failed to start subscription.\nPlease try again later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(isJapanese ? 'OK' : 'OK'),
          ),
        ],
      ),
    );
  }
} 
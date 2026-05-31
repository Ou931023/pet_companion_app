import 'package:flutter/material.dart';

/// 新手導覽 / 功能說明的單頁資料（長者友善：大圖示、大字、白話）。
class FeatureTourPage {
  const FeatureTourPage({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;
}

/// 長者端功能說明頁（首次導覽與首頁「？」重看共用同一份內容）。
///
/// 全部白話、溫暖；**不出現任何工程 / 監控 / 警報字眼**。
const List<FeatureTourPage> featureTourPages = [
  FeatureTourPage(
    icon: Icons.pets,
    title: '歡迎使用愛陪伴',
    body: '我是你的陪伴寵物，會在這裡陪你聊天、陪你過每一天。',
  ),
  FeatureTourPage(
    icon: Icons.mic_none,
    title: '想說話就點麥克風',
    body: '點一下中間的大麥克風，就能直接跟我說話，不用打字。',
  ),
  FeatureTourPage(
    icon: Icons.favorite_border,
    title: '我會記得你說的事',
    body: '你說過的重要事情我會記得，下次自然地和你聊起。',
  ),
  FeatureTourPage(
    icon: Icons.volunteer_activism,
    title: '有需要不會孤單',
    body: '需要時，系統會協助提醒照護人員，讓你不是一個人。',
  ),
  FeatureTourPage(
    icon: Icons.backpack_outlined,
    title: '寵物狀態與背包',
    body: '你可以看看寵物狀態，也可以使用背包裡的物品。',
  ),
  FeatureTourPage(
    icon: Icons.help_outline,
    title: '忘記也沒關係',
    body: '首頁右上角的問號，可以再看一次這份說明。',
  ),
];

/// 開啟功能說明（首頁「？」用）。以全螢幕對話框呈現，看完關閉回首頁。
Future<void> showFeatureTour(BuildContext context) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (ctx) => FeatureTourView(
        pages: featureTourPages,
        finishLabel: '開始使用',
        onFinish: () => Navigator.of(ctx).maybePop(),
        onSkip: () => Navigator.of(ctx).maybePop(),
      ),
    ),
  );
}

/// 多頁導覽元件：上一個 / 略過 / 下一個，最後一頁顯示 [finishLabel]。
class FeatureTourView extends StatefulWidget {
  const FeatureTourView({
    super.key,
    required this.pages,
    required this.onFinish,
    this.onSkip,
    this.finishLabel = '開始使用',
  });

  final List<FeatureTourPage> pages;

  /// 最後一頁按下 [finishLabel] 時呼叫。
  final VoidCallback onFinish;

  /// 點「略過」時呼叫；未提供則等同 [onFinish]。
  final VoidCallback? onSkip;

  final String finishLabel;

  @override
  State<FeatureTourView> createState() => _FeatureTourViewState();
}

class _FeatureTourViewState extends State<FeatureTourView> {
  final PageController _pageController = PageController();
  int _index = 0;

  bool get _isLast => _index >= widget.pages.length - 1;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goTo(int next) {
    _pageController.animateToPage(
      next,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _handleNext() {
    if (_isLast) {
      widget.onFinish();
    } else {
      _goTo(_index + 1);
    }
  }

  void _handleSkip() {
    (widget.onSkip ?? widget.onFinish)();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
          child: Column(
            children: [
              // 略過（右上角，低調但清楚）。
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _handleSkip,
                  child: const Text(
                    '略過',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: widget.pages.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (context, i) => _buildPage(widget.pages[i]),
                ),
              ),
              const SizedBox(height: 16),
              _buildDots(),
              const SizedBox(height: 16),
              _buildControls(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPage(FeatureTourPage page) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 160,
          height: 160,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.10),
            shape: BoxShape.circle,
          ),
          child: Icon(
            page.icon,
            size: 84,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(height: 32),
        Text(
          page.title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          page.body,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 21,
            height: 1.5,
            color: Colors.grey.shade700,
          ),
        ),
      ],
    );
  }

  Widget _buildDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(widget.pages.length, (i) {
        final active = i == _index;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 22 : 10,
          height: 10,
          decoration: BoxDecoration(
            color: active
                ? Theme.of(context).colorScheme.primary
                : Colors.grey.shade300,
            borderRadius: BorderRadius.circular(999),
          ),
        );
      }),
    );
  }

  Widget _buildControls() {
    return Row(
      children: [
        // 上一個：第一頁時隱藏，保留版面。
        Expanded(
          child: _index > 0
              ? OutlinedButton(
                  onPressed: () => _goTo(_index - 1),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text(
                    '上一個',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton(
            onPressed: _handleNext,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: Text(
              _isLast ? widget.finishLabel : '下一個',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ],
    );
  }
}

import 'dart:async';
import 'package:flutter/material.dart';

/// A premium, minimalist marquee text widget that automatically scrolls
/// horizontally if the text overflows the available width.
class MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final TextAlign textAlign;
  final Duration scrollDuration;
  final Duration pauseDuration;

  const MarqueeText({
    super.key,
    required this.text,
    required this.style,
    this.textAlign = TextAlign.center,
    this.scrollDuration = const Duration(seconds: 10),
    this.pauseDuration = const Duration(seconds: 2),
  });

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText> {
  late final ScrollController _scrollController;
  bool _scrollingActive = false;
  Timer? _scrollTimer;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAndStartScroll());
  }

  @override
  void didUpdateWidget(MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _stopScroll();
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0.0);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkAndStartScroll());
    }
  }

  @override
  void dispose() {
    _stopScroll();
    _scrollController.dispose();
    super.dispose();
  }

  void _stopScroll() {
    _scrollingActive = false;
    _scrollTimer?.cancel();
    _scrollTimer = null;
  }

  void _checkAndStartScroll() {
    if (!mounted || !_scrollController.hasClients) return;
    
    final maxScroll = _scrollController.position.maxScrollExtent;
    if (maxScroll > 0) {
      _scrollingActive = true;
      _runScrollCycle();
    }
  }

  Future<void> _runScrollCycle() async {
    while (mounted && _scrollingActive) {
      // Pause at start position
      await Future.delayed(widget.pauseDuration);
      if (!mounted || !_scrollingActive) break;

      final maxScroll = _scrollController.position.maxScrollExtent;
      if (maxScroll <= 0) break;

      // Scroll to end
      await _scrollController.animateTo(
        maxScroll,
        duration: widget.scrollDuration,
        curve: Curves.easeInOut,
      );
      
      // Pause at end position
      await Future.delayed(widget.pauseDuration);
      if (!mounted || !_scrollingActive) break;

      // Scroll back to start
      await _scrollController.animateTo(
        0.0,
        duration: widget.scrollDuration,
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _scrollController,
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      child: Text(
        widget.text,
        style: widget.style,
        textAlign: widget.textAlign,
      ),
    );
  }
}

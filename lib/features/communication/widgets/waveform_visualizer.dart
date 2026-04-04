import 'dart:math';
import 'package:flutter/material.dart';
import '../../../app/constants.dart';

class WaveformVisualizer extends StatefulWidget {
  final bool isRecording;
  final int barCount;

  const WaveformVisualizer({
    super.key,
    required this.isRecording,
    this.barCount = 20,
  });

  @override
  State<WaveformVisualizer> createState() => _WaveformVisualizerState();
}

class _WaveformVisualizerState extends State<WaveformVisualizer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final Random _random = Random();
  List<double> _barHeights = [];

  @override
  void initState() {
    super.initState();
    _barHeights = List.generate(widget.barCount, (_) => 8.0);
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 150),
    )..addListener(() {
        if (widget.isRecording) {
          setState(() {
            _barHeights = List.generate(
              widget.barCount,
              (_) => 8.0 + _random.nextDouble() * 32.0,
            );
          });
        }
      });
  }

  @override
  void didUpdateWidget(WaveformVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isRecording && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.isRecording && _controller.isAnimating) {
      _controller.stop();
      setState(() {
        _barHeights = List.generate(widget.barCount, (_) => 8.0);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 64,
      padding: EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(widget.barCount, (index) {
          return AnimatedContainer(
            duration: Duration(milliseconds: 120),
            curve: Curves.easeOut,
            width: 4,
            height: _barHeights[index],
            decoration: BoxDecoration(
              color: widget.isRecording
                  ? AppColors.primary.withOpacity(0.7 + (_barHeights[index] / 40) * 0.3)
                  : AppColors.outlineVariant.withOpacity(0.5),
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }),
      ),
    );
  }
}

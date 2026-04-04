import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../../app/constants.dart';
import '../../../shared/widgets/kawan_app_bar.dart';
import '../../../shared/widgets/bottom_nav_bar.dart';
import '../../../core/providers/communication_provider.dart';
import '../../../shared/models/conversation_entry.dart';
import '../../../shared/models/user_persona.dart';
import 'package:intl/intl.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(conversationHistoryProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: KawanAppBar(
        title: 'Riwayat',
        showBackButton: true,
      ),
      body: entries.isEmpty
          ? _buildEmptyState()
          : ListView.separated(
              physics: BouncingScrollPhysics(),
              padding: EdgeInsets.all(AppSpacing.xxl),
              itemCount: entries.length,
              separatorBuilder: (context, index) =>
                  SizedBox(height: AppSpacing.md),
              itemBuilder: (context, index) {
                final entry = entries[index];
                return _buildHistoryCard(entry, index);
              },
            ),
      bottomNavigationBar: BottomNavBar(
        currentIndex: 1,
        onTap: (index) => _handleNavTap(context, index),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.history_rounded,
            size: 64,
            color: AppColors.outlineVariant,
          ),
          SizedBox(height: 16),
          Text(
            'Belum ada riwayat percakapan',
            style: GoogleFonts.beVietnamPro(
              fontSize: 15,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryCard(ConversationEntry entry, int index) {
    final timeStr = _formatTime(entry.timestamp);
    final isSign = entry.type == ConversationType.signToText;

    return Container(
      padding: EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isSign
                      ? AppColors.primary.withOpacity(0.1)
                      : AppColors.accent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    entry.type.icon,
                    style: TextStyle(fontSize: 18),
                  ),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.type.label,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isSign ? AppColors.primary : AppColors.accent,
                      ),
                    ),
                    Text(
                      timeStr,
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                child: Text(
                  entry.sourcePersona.displayName,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: AppSpacing.md),
          // Original text
          if (isSign)
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: entry.originalText.split(' ').map((word) {
                return Container(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Text(
                    word,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                );
              }).toList(),
            )
          else
            Text(
              entry.originalText,
              style: GoogleFonts.beVietnamPro(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          SizedBox(height: AppSpacing.sm),
          // Divider replacement (spacing)
          Container(
            height: 1,
            color: AppColors.outlineVariant.withOpacity(0.15),
          ),
          SizedBox(height: AppSpacing.sm),
          // Translated text
          Text(
            entry.translatedText,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
              height: 1.4,
            ),
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(
          duration: 300.ms,
          delay: Duration(milliseconds: index * 80),
        )
        .slideY(
          begin: 0.05,
          end: 0,
          duration: 300.ms,
          delay: Duration(milliseconds: index * 80),
          curve: Curves.easeOut,
        );
  }

  String _formatTime(DateTime timestamp) {
    final now = DateTime.now();
    final diff = now.difference(timestamp);

    if (diff.inMinutes < 60) {
      return '${diff.inMinutes} menit lalu';
    }
    if (diff.inHours < 24) {
      return '${diff.inHours} jam lalu';
    }
    return DateFormat('dd MMM, HH:mm', 'id').format(timestamp);
  }

  void _handleNavTap(BuildContext context, int index) {
    switch (index) {
      case 0:
        context.go('/home');
        break;
      case 1:
        break; // Already on history
      case 2:
        context.push('/learn');
        break;
      case 3:
        context.push('/settings');
        break;
    }
  }
}

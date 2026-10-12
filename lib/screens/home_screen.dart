import 'dart:async';

import 'package:flutter/material.dart';

import '../services/apps_controller.dart';
import '../services/catalog.dart';
import '../theme.dart';
import '../widgets/app_card.dart';

/// Jeti's one screen: every app, with what's installed and what's new.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller});

  final AppsController controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  AppsController get controller => widget.controller;
  late final AppLifecycleListener _lifecycle;
  late final Timer _recheck;

  @override
  void initState() {
    super.initState();
    controller.confirmClose = _confirmClose;
    controller.refresh();
    // Coming back to Jeti picks up apps installed or removed meanwhile.
    _lifecycle = AppLifecycleListener(onResume: controller.refreshInstalled);
    // For a Jeti left open for a long time.
    _recheck = Timer.periodic(const Duration(hours: 6), (_) => controller.refresh());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _recheck.cancel();
    controller.dispose();
    super.dispose();
  }

  Future<bool> _confirmClose(CatalogApp app) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Close ${app.title}?'),
        content: Text("${app.title} is open. Jeti will close it to update it, then open it again."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not now')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Close and update')),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _Centered(child: _Header(controller: controller))),
            if (controller.jetiUpdate != null)
              SliverToBoxAdapter(child: _Centered(child: _JetiUpdateBanner(controller: controller))),
            ..._body(context),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }

  List<Widget> _body(BuildContext context) {
    if (controller.entries.isEmpty) {
      final Widget child;
      if (controller.loadError != null) {
        child = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 40, color: AppColors.textTertiary),
            const SizedBox(height: 12),
            Text(controller.loadError!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: controller.refresh, child: const Text('Try again')),
          ],
        );
      } else if (controller.loading) {
        child = const CircularProgressIndicator();
      } else {
        child = const Text('No apps yet.');
      }
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(padding: const EdgeInsets.all(32), child: Center(child: child)),
        ),
      ];
    }
    return [
      SliverList.separated(
        itemCount: controller.entries.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, i) => _Centered(
          child: AppCard(entry: controller.entries[i], controller: controller),
        ),
      ),
    ];
  }
}

/// Keeps content to a readable width in a wide window.
class _Centered extends StatelessWidget {
  const _Centered({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880),
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: child),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller});

  final AppsController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final updates = controller.updatable.length;
    final checking = controller.loading || controller.entries.any((e) => e.checking);

    final String summary;
    if (checking) {
      summary = 'Checking for updates…';
    } else if (controller.entries.isEmpty) {
      summary = 'Apps by BersamaMus';
    } else if (updates > 0) {
      summary = updates == 1 ? '1 update available' : '$updates updates available';
    } else if (controller.entries.every((e) => e.installed == null)) {
      summary = 'Apps by BersamaMus, ready to install';
    } else {
      summary = "Everything's up to date";
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 32, 0, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset('assets/icon.png', width: 48, height: 48, filterQuality: FilterQuality.medium),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Jeti', style: theme.textTheme.headlineMedium),
                    const SizedBox(height: 2),
                    Text(summary, style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Check for updates',
                onPressed: checking || controller.busy ? null : controller.refresh,
                icon: const Icon(Icons.refresh_rounded),
              ),
              if (updates > 0) ...[
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: controller.updatable.every((e) => e.task != null) ? null : controller.updateAll,
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: Text(updates == 1 ? 'Update ${controller.updatable.first.app.title}' : 'Update all ($updates)'),
                ),
              ],
            ],
          ),
          if (controller.catalogFromCache) ...[
            const SizedBox(height: 16),
            Text(
              "Couldn't reach bersamamus.com, so this is the list from last time.",
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _JetiUpdateBanner extends StatelessWidget {
  const _JetiUpdateBanner({required this.controller});

  final AppsController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = controller.jetiUpdateProgress;
    final error = controller.jetiUpdateError;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 14, 14),
        decoration: BoxDecoration(
          color: AppColors.accentFaint,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.accentSoft),
        ),
        child: Row(
          children: [
            const Icon(Icons.auto_awesome_rounded, color: AppColors.accent, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Jeti ${controller.jetiUpdate!.version} is out', style: theme.textTheme.titleMedium),
                  if (error != null)
                    Text(error, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.danger))
                  else if (progress != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: LinearProgressIndicator(value: progress, borderRadius: BorderRadius.circular(4)),
                    )
                  else
                    Text("It updates in a moment and opens again.", style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: progress != null || controller.busy ? null : controller.updateJeti,
              child: const Text('Update Jeti'),
            ),
          ],
        ),
      ),
    );
  }
}

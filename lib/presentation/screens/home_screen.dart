import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';
import '../app_controller.dart';
import '../theme.dart';
import '../widgets.dart';
import '../compact_header.dart';
import 'item_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    required this.onAdd,
    required this.onSeeAll,
    required this.onStatusSelected,
    required this.onSelectTab,
    super.key,
  });
  final VoidCallback onAdd;
  final VoidCallback onSeeAll;
  final ValueChanged<WarrantyStatus> onStatusSelected;
  final ValueChanged<int> onSelectTab;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with AutomaticKeepAliveClientMixin {
  String query = '';
  bool searchOpen = false;
  final searchController = TextEditingController();

  void closeSearch() {
    FocusScope.of(context).unfocus();
    searchController.clear();
    setState(() { query = ''; searchOpen = false; });
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }
  @override
  bool get wantKeepAlive => true;
  @override
  Widget build(BuildContext context) {
    super.build(context);
    final app = context.watch<AppController>();
    final filtered =
        app.items
            .where(
              (item) =>
                  '${item.productName} ${item.brand} ${item.model} '
                          '${item.serialNumber} ${item.store} ${item.location} '
                          '${item.servicePhone} ${item.serviceEmail}'
                      .toLowerCase()
                      .contains(query.toLowerCase()),
            )
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final expiring =
        app.items
            .where(
              (i) =>
                  i.status(thresholdDays: app.settings.expiringThresholdDays) ==
                  WarrantyStatus.expiringSoon,
            )
            .toList()
          ..sort((a, b) => a.expiryDate.compareTo(b.expiryDate));
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: app.refreshCloud,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          children: [
            CaveHeader(
              title: 'WarrantyCave',
              brand: true,
              subtitle: context.l10n.text('homeCaveSubtitle'),
              actions: [
                IconButton(
                  tooltip: context.l10n.text('searchWarranties'),
                  onPressed: () => searchOpen ? closeSearch()
                      : setState(() => searchOpen = true),
                  icon: Icon(searchOpen ? Icons.search_off : Icons.search),
                ),
                TextButton.icon(
                  onPressed: widget.onAdd,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  icon: const Icon(Icons.add_circle_outline, size: 21),
                  label: Text(context.l10n.text('add')),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(context.l10n.text('goodToSeeYou'),
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800,
                color: Theme.of(context).colorScheme.onSurface)),
            if (searchOpen) CompactSearchField(
              controller: searchController,
              onChanged: (v) => setState(() => query = v),
              onClose: closeSearch,
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, c) => Row(
                children: [
                  _Metric(
                    label: context.l10n.text('active'),
                    count: app.countFor(WarrantyStatus.active),
                    color: caveTeal,
                    icon: Icons.shield_outlined,
                    onTap: () => widget.onStatusSelected(WarrantyStatus.active),
                  ),
                  const SizedBox(width: 8),
                  _Metric(
                    label: context.l10n.text('expiring'),
                    count: app.countFor(WarrantyStatus.expiringSoon),
                    color: Colors.orange,
                    icon: Icons.schedule,
                    onTap: () =>
                        widget.onStatusSelected(WarrantyStatus.expiringSoon),
                  ),
                  const SizedBox(width: 8),
                  _Metric(
                    label: context.l10n.text('expired'),
                    count: app.countFor(WarrantyStatus.expired),
                    color: Colors.redAccent,
                    icon: Icons.close,
                    onTap: () =>
                        widget.onStatusSelected(WarrantyStatus.expired),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SectionTitle(
              query.isEmpty
                  ? context.l10n.text('recentlyAdded')
                  : context.l10n.text('searchResults'),
              action: TextButton(
                onPressed: widget.onSeeAll,
                child: Text(context.l10n.text('seeAll')),
              ),
            ),
            const SizedBox(height: 12),
            if (filtered.isEmpty)
              _Empty(onAdd: widget.onAdd)
            else
              ...filtered.take(6).map((item) => _itemCard(context, app, item)),
            if (expiring.isNotEmpty) ...[
              const SizedBox(height: 14),
              SectionTitle(context.l10n.text('expiringSoon')),
              const SizedBox(height: 12),
              ...expiring.take(3).map((item) => _itemCard(context, app, item)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _itemCard(
    BuildContext context,
    AppController app,
    WarrantyItem item,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: WarrantyCard(
      item: item,
      threshold: app.settings.expiringThresholdDays,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ItemDetailScreen(
            itemId: item.id,
            onSelectTab: widget.onSelectTab,
          ),
        ),
      ),
    ),
  );
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.count,
    required this.color,
    required this.icon,
    required this.onTap,
  });
  final String label;
  final int count;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          child: Column(
            children: [
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, color: color, size: 19),
                const SizedBox(width: 6),
                Flexible(child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              )),
              ]),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onAdd});
  final VoidCallback onAdd;
  @override
  Widget build(BuildContext context) => AppEmptyStates(
    title: context.l10n.text('noWarranties'),
    message: context.l10n.text('addFirst'),
    actionLabel: context.l10n.text('addWarranty'),
    onAction: onAdd,
  );
}


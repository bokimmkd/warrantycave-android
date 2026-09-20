import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';
import '../app_controller.dart';
import '../theme.dart';
import '../widgets.dart';
import 'item_detail_screen.dart';

enum ItemSort {
  expiry,
  recentlyAdded,
  purchaseNewest,
  purchaseOldest,
  productName,
}

class ItemsScreen extends StatefulWidget {
  const ItemsScreen({super.key, this.initialStatus, required this.onSelectTab});
  final WarrantyStatus? initialStatus;
  final ValueChanged<int> onSelectTab;
  @override
  State<ItemsScreen> createState() => _ItemsScreenState();
}

class _ItemsScreenState extends State<ItemsScreen>
    with AutomaticKeepAliveClientMixin {
  String query = '';
  late WarrantyStatus? status = widget.initialStatus;
  String? type;
  String? location;
  ItemSort sort = ItemSort.expiry;
  final searchController = TextEditingController();
  @override
  void didUpdateWidget(covariant ItemsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialStatus != widget.initialStatus) {
      setState(() => status = widget.initialStatus);
    }
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> showFilters(List<String> types, List<String> locations) async {
    var draftStatus = status;
    var draftType = type;
    var draftLocation = location;
    await AppBottomSheets.show<void>(
      context,
      title: context.l10n.text('filterWarranties'),
      child: StatefulBuilder(
        builder: (sheetContext, update) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                context.l10n.text('status').toUpperCase(),
                style: AppTypography.label,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [null, ...WarrantyStatus.values].map((value) {
                final label = value == null
                    ? context.l10n.text('all')
                    : switch (value) {
                        WarrantyStatus.active => context.l10n.text('active'),
                        WarrantyStatus.expiringSoon => context.l10n.text(
                          'expiringSoon',
                        ),
                        WarrantyStatus.expired => context.l10n.text('expired'),
                      };
                return ChoiceChip(
                  label: Text(label),
                  selected: draftStatus == value,
                  onSelected: (_) => update(() => draftStatus = value),
                );
              }).toList(),
            ),
            const SizedBox(height: 18),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                context.l10n.text('productType').toUpperCase(),
                style: AppTypography.label,
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String?>(
              initialValue: draftType,
              decoration: AppInputFields.decoration(
                label: context.l10n.text('productType'),
              ),
              items: [
                DropdownMenuItem(
                  value: null,
                  child: Text(context.l10n.text('allProductTypes')),
                ),
                ...types.map((e) => DropdownMenuItem(value: e, child: Text(e))),
              ],
              onChanged: (v) => update(() => draftType = v),
            ),
            const SizedBox(height: 18),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                context.l10n.text('location').toUpperCase(),
                style: AppTypography.label,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [null, ...locations]
                  .map(
                    (value) => ChoiceChip(
                      label: Text(value ?? context.l10n.text('allLocations')),
                      selected: draftLocation == value,
                      onSelected: (_) => update(() => draftLocation = value),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlineButton(
                    label: context.l10n.text('reset'),
                    icon: Icons.refresh,
                    onPressed: () {
                      update(() {
                        draftStatus = null;
                        draftType = null;
                        draftLocation = null;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: PrimaryButton(
                    label: context.l10n.text('apply'),
                    icon: Icons.check,
                    expand: false,
                    onPressed: () {
                      setState(() {
                        status = draftStatus;
                        type = draftType;
                        location = draftLocation;
                      });
                      Navigator.pop(sheetContext);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> showSort() async {
    final picked = await AppBottomSheets.show<ItemSort>(
      context,
      title: context.l10n.text('sortWarranties'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: ItemSort.values
            .map(
              (value) => ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.medium),
                ),
                tileColor: value == sort
                    ? AppColors.softBlue
                    : Colors.transparent,
                trailing: Icon(
                  value == sort ? Icons.check_circle : Icons.circle_outlined,
                  color: value == sort ? caveTeal : AppColors.border,
                ),
                title: Text(switch (value) {
                  ItemSort.expiry => context.l10n.text('expirySoonest'),
                  ItemSort.recentlyAdded => context.l10n.text('recentlyAdded'),
                  ItemSort.purchaseNewest => context.l10n.text(
                    'purchaseNewest',
                  ),
                  ItemSort.purchaseOldest => context.l10n.text(
                    'purchaseOldest',
                  ),
                  ItemSort.productName => context.l10n.text('productName'),
                }),
                onTap: () => Navigator.pop(context, value),
              ),
            )
            .toList(),
      ),
    );
    if (picked != null) setState(() => sort = picked);
  }

  @override
  bool get wantKeepAlive => true;
  @override
  Widget build(BuildContext context) {
    super.build(context);
    final app = context.watch<AppController>();
    var data = app.items
        .where(
          (i) =>
              '${i.productName} ${i.brand} ${i.model} ${i.serialNumber} ${i.store} ${i.location} ${i.servicePhone} ${i.serviceEmail}'
                  .toLowerCase()
                  .contains(query.toLowerCase()) &&
              (status == null ||
                  i.status(thresholdDays: app.settings.expiringThresholdDays) ==
                      status) &&
              (type == null || i.productType == type) &&
              (location == null || i.location == location),
        )
        .toList();
    switch (sort) {
      case ItemSort.expiry:
        data.sort((a, b) => a.expiryDate.compareTo(b.expiryDate));
      case ItemSort.purchaseNewest:
        data.sort((a, b) => b.purchaseDate.compareTo(a.purchaseDate));
      case ItemSort.purchaseOldest:
        data.sort((a, b) => a.purchaseDate.compareTo(b.purchaseDate));
      case ItemSort.recentlyAdded:
        data.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case ItemSort.productName:
        data.sort(
          (a, b) => a.productName.toLowerCase().compareTo(
            b.productName.toLowerCase(),
          ),
        );
    }
    final types = app.items.map((e) => e.productType).toSet().toList()..sort();
    final locations =
        app.items
            .map((e) => e.location)
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: app.refreshCloud,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    switch (status) {
                      WarrantyStatus.active => context.l10n.text(
                        'activeWarranties',
                      ),
                      WarrantyStatus.expiringSoon => context.l10n.text(
                        'expiringSoon',
                      ),
                      WarrantyStatus.expired => context.l10n.text(
                        'expiredWarranties',
                      ),
                      null => context.l10n.text('myItems'),
                    },
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: caveNavy,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: searchController,
                    onChanged: (v) => setState(() => query = v),
                    decoration: AppInputFields.decoration(
                      label: context.l10n.text('search'),
                      hint: context.l10n.text('searchHint'),
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: context.l10n.text('clearSearch'),
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                searchController.clear();
                                setState(() => query = '');
                              },
                            ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (status != null) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: InputChip(
                        label: Text(switch (status!) {
                          WarrantyStatus.active => context.l10n.text('active'),
                          WarrantyStatus.expiringSoon => context.l10n.text(
                            'expiringSoon',
                          ),
                          WarrantyStatus.expired => context.l10n.text(
                            'expired',
                          ),
                        }),
                        avatar: const Icon(Icons.check, size: 17),
                        onDeleted: () => setState(() => status = null),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: SecondaryButton(
                          label:
                              status == null && type == null && location == null
                              ? context.l10n.text('filters')
                              : context.l10n.text('filtersActive'),
                          icon: Icons.tune,
                          onPressed: () => showFilters(types, locations),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SecondaryButton(
                          label: context.l10n.text('sort'),
                          icon: Icons.swap_vert,
                          onPressed: showSort,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: data.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(20),
                      children: [
                        AppEmptyStates(
                          title: app.items.isEmpty
                              ? context.l10n.text('noWarranties')
                              : context.l10n.text('noMatches'),
                          message: app.items.isEmpty
                              ? context.l10n.text('addFirst')
                              : context.l10n.text('tryAnother'),
                          icon: app.items.isEmpty
                              ? Icons.inventory_2_outlined
                              : Icons.search_off_rounded,
                        ),
                      ],
                    )
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                      itemCount: data.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final item = data[index];
                        return WarrantyCard(
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
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

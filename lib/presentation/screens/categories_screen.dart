import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../domain/category_catalog.dart';
import '../../domain/models.dart';
import '../../l10n/app_localizations.dart';
import '../app_controller.dart';
import '../theme.dart';
import '../widgets.dart';

Future<String?> editCategory(BuildContext context, {String? id}) async {
  final app = context.read<AppController>();
  final owner = app.user?.uid;
  final controller = TextEditingController(text: id == null ? '' : context.l10n.productLabel(id, app.settings));
  final form = GlobalKey<FormState>();
  final label = await showDialog<String>(context: context, builder: (dialogContext) => AlertDialog(
    title: Text(context.l10n.text(id == null ? 'addCategory' : 'renameCategory')),
    content: Form(key: form, child: TextFormField(
      controller: controller, autofocus: true, maxLength: 80,
      decoration: InputDecoration(labelText: context.l10n.text('categoryName')),
      validator: (value) {
        final name = value?.trim() ?? '';
        if (name.isEmpty) return context.l10n.text('categoryName');
        if (categoryIds(app.settings, app.items).any((other) => other != id &&
            context.l10n.productLabel(other, app.settings).toLowerCase() == name.toLowerCase())) {
          return context.l10n.text('categoryDuplicate');
        }
        return null;
      },
    )),
    actions: [
      TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(context.l10n.text('cancel'))),
      FilledButton(onPressed: () { if (form.currentState!.validate()) Navigator.pop(dialogContext, controller.text.trim()); },
        child: Text(context.l10n.text('save'))),
    ],
  ));
  // Dispose after the route has finished removing its editable field.
  WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
  if (label == null || !context.mounted || app.user?.uid != owner) return null;
  try { return await app.saveCategory(id: id, name: label); }
  catch (_) { if (context.mounted) AppSnackbars.error(context, context.l10n.text('saveFailed')); return null; }
}

class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key, this.onSelectTab, this.selectedTab = 4});

  final ValueChanged<int>? onSelectTab;
  final int selectedTab;

  Future<void> remove(BuildContext context, String id) async {
    final app = context.read<AppController>();
    final owner = app.user?.uid;
    final count = app.items.where((e) => e.productType == id).length;
    final choices = categoryIds(app.settings, app.items).where((e) => e != id).toList();
    String? replacement = count == 0 ? 'Other' : null;
    final selected = await showDialog<String>(context: context, builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, update) => AlertDialog(
        title: Text(context.l10n.text('deleteCategory')),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(count > 0 ? context.l10n.format('categoryUsed', {'count': count}) : context.l10n.text('categoryUnused')),
          if (count > 0) ...[
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: replacement, isExpanded: true,
              decoration: InputDecoration(labelText: context.l10n.text('categoryReplacement')),
              items: choices.map((e) => DropdownMenuItem(value: e,
                child: Text(context.l10n.productLabel(e, app.settings), overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (value) => update(() => replacement = value),
            ),
          ],
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(context.l10n.text('cancel'))),
          FilledButton(onPressed: replacement == null ? null : () => Navigator.pop(dialogContext, replacement),
            child: Text(context.l10n.text('deleteCategory'))),
        ],
      ),
    ));
    if (selected == null || !context.mounted || app.user?.uid != owner) return;
    try {
      await app.saveCategory(id: id, name: context.l10n.productLabel(id, app.settings), replacement: selected);
    } catch (_) { if (context.mounted) AppSnackbars.error(context, context.l10n.text('saveFailed')); }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final ids = categoryIds(app.settings, app.items);
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.text('manageCategories'))),
      body: SafeArea(top: false, child: ListView(padding: const EdgeInsets.all(16), children: [
        FilledButton.icon(onPressed: app.accountActionBusy ? null : () => editCategory(context),
          icon: const Icon(Icons.add), label: Text(context.l10n.text('addCategory'))),
        const SizedBox(height: 12),
        for (final id in ids) Card(child: ListTile(
          leading: Icon(iconForType(id)),
          title: Text(context.l10n.productLabel(id, app.settings)),
          onTap: app.accountActionBusy ? null : () => editCategory(context, id: id),
          trailing: PopupMenuButton<String>(
            enabled: !app.accountActionBusy,
            onSelected: (action) { if (action == 'rename') { editCategory(context, id: id); } else { remove(context, id); } },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'rename', child: Text(context.l10n.text('renameCategory'))),
              // Keep one stable fallback for concurrent/offline replacements.
              if (id != 'Other') PopupMenuItem(value: 'delete', child: Text(context.l10n.text('deleteCategory'))),
            ],
          ),
        )),
      ])),
      bottomNavigationBar: onSelectTab == null ? null : AppBottomNavigation(
        selectedIndex: selectedTab,
        onSelected: onSelectTab!,
      ),
    );
  }
}

class ProductTypeSheet extends StatefulWidget {
  const ProductTypeSheet({super.key});
  @override
  State<ProductTypeSheet> createState() => _ProductTypeSheetState();
}
class _ProductTypeSheetState extends State<ProductTypeSheet> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final options = categoryIds(app.settings, app.items).where((id) =>
      context.l10n.productLabel(id, app.settings).toLowerCase().contains(query.toLowerCase())).toList();
    String group(String id) => productTypes.where((e) => e.name == id).firstOrNull?.category ?? 'myCategories';
    final groups = options.map(group).toSet();
    return SafeArea(child: Padding(padding: EdgeInsets.fromLTRB(20,20,20,20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(height: MediaQuery.sizeOf(context).height * .72,
        child: Column(children: [
          Text(context.l10n.text('chooseProductType'), style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          TextField(onChanged: (value) => setState(() => query = value),
            decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: context.l10n.text('searchProductTypes'))),
          TextButton.icon(onPressed: app.accountActionBusy ? null : () async {
            final id = await editCategory(context);
            if (id != null && context.mounted) Navigator.pop(context, id);
          }, icon: const Icon(Icons.add), label: Text(context.l10n.text('addCategory'))),
          Expanded(child: ListView(children: [for (final category in groups) ...[
            Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(context.l10n.text(category),
              style: Theme.of(context).textTheme.titleSmall)),
            for (final id in options.where((e) => group(e) == category)) ListTile(
              leading: Icon(iconForType(id)), title: Text(context.l10n.productLabel(id, app.settings)),
              onTap: () => Navigator.pop(context, id)),
          ]])),
        ]),
      ),
    ));
  }
}

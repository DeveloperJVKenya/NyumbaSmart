import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';
import 'package:cmms/models/bim_model.dart';
import 'package:cmms/models/equipment.dart';
import 'package:cmms/providers/auth_providers.dart';
import 'package:cmms/screens/bim/bim_import_screen.dart';
import 'package:cmms/screens/bim/bim_widgets.dart';
import 'package:cmms/theme/app_theme.dart';
import 'package:cmms/theme/app_widgets.dart';
import 'package:cmms/widgets/responsive_screen_wrapper.dart';

/// Floors and rooms of a facility (facilities/{facilityId}/spaces), with the equipment in each.
/// Filled by BIM imports; admins can also add/edit spaces by hand for facilities without BIM files.
class SpacesScreen extends ConsumerStatefulWidget {
  final String facilityId;

  const SpacesScreen({super.key, required this.facilityId});

  @override
  ConsumerState<SpacesScreen> createState() => _SpacesScreenState();
}

class _SpacesScreenState extends ConsumerState<SpacesScreen> {
  final Logger _logger = Logger();
  final _searchController = TextEditingController();
  String _query = '';

  late final Stream<QuerySnapshot<Map<String, dynamic>>> _spacesStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _equipmentStream;

  CollectionReference<Map<String, dynamic>> get _spacesCol =>
      FirebaseFirestore.instance.collection('facilities').doc(widget.facilityId).collection('spaces');

  @override
  void initState() {
    super.initState();
    _spacesStream = _spacesCol.snapshots();
    _equipmentStream =
        FirebaseFirestore.instance.collection('facilities').doc(widget.facilityId).collection('equipment').snapshots();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canManage = canManageBim(ref.watch(currentUserRoleProvider).value);
    return ResponsiveScreenWrapper(
      title: 'Floors & Rooms',
      facilityId: widget.facilityId,
      currentRole: 'User',
      organization: '-',
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () => _editSpace(null, const []),
              backgroundColor: AppColors.primary,
              icon: const Icon(Icons.add_rounded, color: Colors.white),
              label: Text('Add floor or room', style: GoogleFonts.poppins(color: Colors.white)),
            )
          : null,
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _spacesStream,
        builder: (context, spaceSnap) {
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _equipmentStream,
            builder: (context, eqSnap) {
              if (spaceSnap.hasError || eqSnap.hasError) {
                _logger.e('Spaces load failed', error: spaceSnap.error ?? eqSnap.error);
                return BimPage(children: [
                  AppErrorBanner(message: 'Could not load floors and rooms: ${spaceSnap.error ?? eqSnap.error}'),
                ]);
              }
              if (!spaceSnap.hasData || !eqSnap.hasData) {
                return const BimPage(children: [AppSkeletonList()]);
              }
              final spaces = spaceSnap.data!.docs.map(BimSpace.fromSnapshot).toList();
              final equipment = eqSnap.data!.docs.map(Equipment.fromSnapshot).toList();
              return _buildContent(spaces, equipment, canManage);
            },
          );
        },
      ),
    );
  }

  Widget _buildContent(List<BimSpace> spaces, List<Equipment> equipment, bool canManage) {
    final storeys = spaces.where((s) => s.kind == BimSpaceKind.storey).toList()
      ..sort((a, b) {
        final byElevation = (a.elevation ?? 0).compareTo(b.elevation ?? 0);
        return byElevation != 0 ? byElevation : a.name.compareTo(b.name);
      });
    final storeyIds = storeys.map((s) => s.id).toSet();
    final rooms = spaces.where((s) => s.kind == BimSpaceKind.space).toList()..sort((a, b) => a.name.compareTo(b.name));

    final equipmentBySpace = <String, List<Equipment>>{};
    for (final e in equipment) {
      if (e.spaceId != null) (equipmentBySpace[e.spaceId!] ??= []).add(e);
    }
    final placed = equipment.where((e) => e.spaceId != null && spaces.any((s) => s.id == e.spaceId)).length;

    final q = _query.trim().toLowerCase();
    bool matches(BimSpace s) =>
        q.isEmpty || s.name.toLowerCase().contains(q) || (s.description ?? '').toLowerCase().contains(q);

    final orphanRooms = rooms.where((r) => r.parentId == null || !storeyIds.contains(r.parentId)).where(matches).toList();

    return BimPage(
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(spacing: 12, runSpacing: 12, children: [
                BimStat(icon: Icons.layers_rounded, label: 'Floors', value: '${storeys.length}'),
                BimStat(icon: Icons.meeting_room_rounded, label: 'Rooms', value: '${rooms.length}'),
                BimStat(
                    icon: Icons.precision_manufacturing_rounded,
                    label: 'Equipment placed',
                    value: '$placed / ${equipment.length}'),
              ]),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: 'Search rooms by number or name',
                  hintStyle: GoogleFonts.poppins(fontSize: 13),
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => setState(() {
                            _searchController.clear();
                            _query = '';
                          }),
                        ),
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md), borderSide: BorderSide.none),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (spaces.isEmpty)
          _buildEmpty(canManage)
        else ...[
          for (final storey in storeys)
            _buildStorey(
              storey,
              rooms.where((r) => r.parentId == storey.id).where(matches).toList(),
              equipmentBySpace,
              spaces,
              canManage,
              forceOpen: q.isNotEmpty,
            ),
          if (orphanRooms.isNotEmpty)
            _buildGroup(
              title: 'Rooms not on a floor',
              icon: Icons.help_outline_rounded,
              rooms: orphanRooms,
              equipmentBySpace: equipmentBySpace,
              allSpaces: spaces,
              canManage: canManage,
              initiallyExpanded: true,
            ),
        ],
      ],
    );
  }

  Widget _buildEmpty(bool canManage) {
    return AppCard(
      child: Column(
        children: [
          const Icon(Icons.apartment_rounded, size: 56, color: AppColors.primaryLight),
          const SizedBox(height: 12),
          Text('No floors or rooms yet',
              style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          const SizedBox(height: 6),
          Text(
            canManage
                ? 'Import a COBie or IFC file to create them automatically, or add them by hand.'
                : 'An administrator can import them from a COBie or IFC file.',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary),
          ),
          if (canManage) ...[
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: 260,
              child: AppGradientButton(
                label: 'Import BIM data',
                icon: Icons.upload_file_rounded,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => BimImportScreen(facilityId: widget.facilityId)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStorey(
    BimSpace storey,
    List<BimSpace> rooms,
    Map<String, List<Equipment>> equipmentBySpace,
    List<BimSpace> allSpaces,
    bool canManage, {
    bool forceOpen = false,
  }) {
    final onFloor = equipmentBySpace[storey.id] ?? const [];
    final inRooms = rooms.fold<int>(0, (n, r) => n + (equipmentBySpace[r.id]?.length ?? 0));
    // While searching, hide floors that neither match nor contain a matching room.
    if (forceOpen && rooms.isEmpty && !storey.name.toLowerCase().contains(_query.trim().toLowerCase())) {
      return const SizedBox.shrink();
    }

    return _buildGroup(
      title: storey.name,
      subtitle: [
        if (storey.description != null) storey.description!,
        if (storey.elevation != null) '${storey.elevation!.toStringAsFixed(2)} m',
        '${rooms.length} room${rooms.length == 1 ? '' : 's'}',
        '${onFloor.length + inRooms} equipment',
      ].join('  ·  '),
      icon: Icons.layers_rounded,
      space: storey,
      rooms: rooms,
      floorEquipment: onFloor,
      equipmentBySpace: equipmentBySpace,
      allSpaces: allSpaces,
      canManage: canManage,
      initiallyExpanded: forceOpen,
    );
  }

  Widget _buildGroup({
    required String title,
    String? subtitle,
    required IconData icon,
    BimSpace? space,
    required List<BimSpace> rooms,
    List<Equipment> floorEquipment = const [],
    required Map<String, List<Equipment>> equipmentBySpace,
    required List<BimSpace> allSpaces,
    required bool canManage,
    bool initiallyExpanded = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.md),
        clipBehavior: Clip.antiAlias,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: PageStorageKey('storey_${space?.id ?? title}_$initiallyExpanded'),
            initiallyExpanded: initiallyExpanded,
            leading: CircleAvatar(
              backgroundColor: AppColors.surfaceAlt,
              child: Icon(icon, color: AppColors.primary, size: 20),
            ),
            title: Row(children: [
              Flexible(
                child: Text(title,
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                    overflow: TextOverflow.ellipsis),
              ),
              if (space?.bimGlobalId != null) ...[
                const SizedBox(width: 8),
                const BimPill(label: 'BIM', color: AppColors.primary),
              ],
            ]),
            subtitle: subtitle == null
                ? null
                : Text(subtitle, style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
            trailing: (canManage && space != null) ? _spaceMenu(space, allSpaces, equipmentBySpace) : null,
            children: [
              if (floorEquipment.isNotEmpty)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.precision_manufacturing_outlined, color: AppColors.textSecondary),
                  title: Text('On this floor (no room)', style: GoogleFonts.poppins(fontSize: 13)),
                  trailing: _countBadge(floorEquipment.length),
                  onTap: () => _showEquipment(title, floorEquipment),
                ),
              if (rooms.isEmpty && floorEquipment.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Text('No rooms on this floor yet.',
                      style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
                ),
              for (final r in rooms)
                ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.only(left: 72, right: 8),
                  leading: const Icon(Icons.meeting_room_outlined, size: 20, color: AppColors.textSecondary),
                  title: Text(r.name, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500)),
                  subtitle: r.description == null
                      ? null
                      : Text(r.description!, style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    _countBadge(equipmentBySpace[r.id]?.length ?? 0),
                    if (canManage) _spaceMenu(r, allSpaces, equipmentBySpace),
                  ]),
                  onTap: () => _showEquipment(r.name, equipmentBySpace[r.id] ?? const []),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _countBadge(int n) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: n == 0 ? AppColors.surface : AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Text('$n', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primaryDark)),
      );

  Widget _spaceMenu(BimSpace space, List<BimSpace> allSpaces, Map<String, List<Equipment>> equipmentBySpace) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded, size: 20),
      onSelected: (v) {
        if (v == 'edit') _editSpace(space, allSpaces);
        if (v == 'delete') _deleteSpace(space, allSpaces, equipmentBySpace);
      },
      itemBuilder: (_) => [
        PopupMenuItem(value: 'edit', child: Text('Edit', style: GoogleFonts.poppins())),
        PopupMenuItem(value: 'delete', child: Text('Delete', style: GoogleFonts.poppins(color: AppColors.error))),
      ],
    );
  }

  void _showEquipment(String title, List<Equipment> items) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        maxChildSize: 0.9,
        builder: (context, controller) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('$title  ·  ${items.length} equipment',
                  style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            Expanded(
              child: items.isEmpty
                  ? Center(child: Text('No equipment in this space.', style: GoogleFonts.poppins(color: AppColors.textSecondary)))
                  : ListView.separated(
                      controller: controller,
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final e = items[i];
                        return ListTile(
                          leading: const Icon(Icons.precision_manufacturing_outlined, color: AppColors.primary),
                          title: Text(e.name, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500)),
                          subtitle: Text(
                            [e.type, if (e.manufacturer != null) e.manufacturer!, if (e.modelNumber != null) e.modelNumber!]
                                .join('  •  '),
                            style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary),
                          ),
                          trailing: Text(e.status, style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editSpace(BimSpace? existing, List<BimSpace> allSpaces) async {
    final nameCtl = TextEditingController(text: existing?.name ?? '');
    final descCtl = TextEditingController(text: existing?.description ?? '');
    final elevCtl = TextEditingController(text: existing?.elevation?.toString() ?? '');
    var kind = existing?.kind ?? BimSpaceKind.space;
    String? parentId = existing?.parentId;
    final storeys = allSpaces.where((s) => s.kind == BimSpaceKind.storey && s.id != existing?.id).toList()
      ..sort((a, b) => (a.elevation ?? 0).compareTo(b.elevation ?? 0));
    if (parentId != null && !storeys.any((s) => s.id == parentId)) parentId = null;
    final formKey = GlobalKey<FormState>();

    final save = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text(existing == null ? 'Add floor or room' : 'Edit ${existing.name}',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          content: SizedBox(
            width: 420,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (existing == null)
                    SegmentedButton<BimSpaceKind>(
                      segments: const [
                        ButtonSegment(value: BimSpaceKind.storey, label: Text('Floor'), icon: Icon(Icons.layers_rounded)),
                        ButtonSegment(value: BimSpaceKind.space, label: Text('Room'), icon: Icon(Icons.meeting_room_rounded)),
                      ],
                      selected: {kind},
                      onSelectionChanged: (s) => setDialog(() => kind = s.first),
                    ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: nameCtl,
                    decoration: InputDecoration(
                      labelText: kind == BimSpaceKind.storey ? 'Floor name (e.g. Level 2)' : 'Room number or name',
                    ),
                    validator: (v) => (v ?? '').trim().isEmpty ? 'Enter a name' : null,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(controller: descCtl, decoration: const InputDecoration(labelText: 'Description (optional)')),
                  const SizedBox(height: 8),
                  if (kind == BimSpaceKind.storey)
                    TextFormField(
                      controller: elevCtl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      decoration: const InputDecoration(labelText: 'Elevation in metres (optional)'),
                      validator: (v) =>
                          (v ?? '').trim().isEmpty || double.tryParse(v!.trim()) != null ? null : 'Enter a number',
                    )
                  else
                    DropdownButtonFormField<String?>(
                      initialValue: parentId,
                      decoration: const InputDecoration(labelText: 'Floor'),
                      items: [
                        const DropdownMenuItem<String?>(value: null, child: Text('Not on a floor')),
                        for (final s in storeys) DropdownMenuItem<String?>(value: s.id, child: Text(s.name)),
                      ],
                      onChanged: (v) => setDialog(() => parentId = v),
                    ),
                  if (existing?.bimGlobalId != null) ...[
                    const SizedBox(height: 12),
                    const BimNotice(
                      message: 'This space came from a BIM import. Your changes are kept until the next import of a '
                          'revised file, which refreshes its name, description and floor.',
                      color: AppColors.warning,
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) Navigator.pop(context, true);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (save != true) return;
    final description = descCtl.text.trim();
    final elevation = double.tryParse(elevCtl.text.trim());
    try {
      if (existing == null) {
        final ref = _spacesCol.doc();
        await ref.set(BimSpace(
          id: ref.id,
          facilityId: widget.facilityId,
          kind: kind,
          name: nameCtl.text.trim(),
          description: description.isEmpty ? null : description,
          parentId: kind == BimSpaceKind.space ? parentId : null,
          elevation: kind == BimSpaceKind.storey ? elevation : null,
          createdAt: DateTime.now(),
        ).toMap());
      } else {
        await _spacesCol.doc(existing.id).update({
          'name': nameCtl.text.trim(),
          'description': description.isEmpty ? null : description,
          if (existing.kind == BimSpaceKind.space) 'parentId': parentId,
          if (existing.kind == BimSpaceKind.storey) 'elevation': elevation,
        });
      }
      _snack(existing == null ? 'Added ${nameCtl.text.trim()}' : 'Saved');
    } on FirebaseException catch (e) {
      _snack(e.code == 'permission-denied' ? 'You do not have permission to edit spaces.' : 'Save failed: ${e.message}');
    }
  }

  Future<void> _deleteSpace(BimSpace space, List<BimSpace> allSpaces, Map<String, List<Equipment>> equipmentBySpace) async {
    final linked = equipmentBySpace[space.id]?.length ?? 0;
    final children = allSpaces.where((s) => s.parentId == space.id).length;
    if (linked > 0 || children > 0) {
      _snack('${space.name} still has ${linked > 0 ? '$linked equipment' : ''}'
          '${linked > 0 && children > 0 ? ' and ' : ''}${children > 0 ? '$children rooms' : ''}. Move them first.');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${space.name}?', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: Text(
          space.bimGlobalId != null
              ? 'This space came from a BIM import and will be created again if the same file is re-imported.'
              : 'This cannot be undone.',
          style: GoogleFonts.poppins(fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _spacesCol.doc(space.id).delete();
      _snack('Deleted ${space.name}');
    } on FirebaseException catch (e) {
      _snack(e.code == 'permission-denied' ? 'You do not have permission to delete spaces.' : 'Delete failed: ${e.message}');
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message, style: GoogleFonts.poppins())));
  }
}

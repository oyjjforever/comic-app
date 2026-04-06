import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/state/app_state.dart';

/// Folder tree sidebar widget - displays hierarchical folder tree
/// with lazy-loaded children and folder selection
class FolderTreeSidebar extends StatelessWidget {
  const FolderTreeSidebar({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final nodes = appState.treeNodes;

    return Container(
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: Theme.of(context).dividerColor, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                const Icon(Icons.folder_open, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Folder Tree',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Tree content
          Expanded(
            child: appState.isTreeLoading && nodes.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: CircularProgressIndicator(),
                    ),
                  )
                : nodes.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        'No folders found',
                        style: TextStyle(color: Colors.grey[500]),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(top: 4),
                    itemCount: nodes.length,
                    itemBuilder: (context, index) {
                      return _TreeNodeWidget(node: nodes[index], level: 0);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Single tree node widget - supports expand/collapse with lazy loading
class _TreeNodeWidget extends StatefulWidget {
  final FolderTreeNode node;
  final int level;

  const _TreeNodeWidget({required this.node, required this.level});

  @override
  State<_TreeNodeWidget> createState() => _TreeNodeWidgetState();
}

class _TreeNodeWidgetState extends State<_TreeNodeWidget> {
  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final isSelected = appState.selectedTreePath == widget.node.fullPath;
    final hasChildren = !widget.node.isLeaf;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Node row
        InkWell(
          onTap: () => _onTap(context),
          child: Container(
            padding: EdgeInsets.only(
              left: 8.0 + (widget.level * 16.0),
              right: 8,
              top: 6,
              bottom: 6,
            ),
            decoration: BoxDecoration(
              color: isSelected
                  ? Theme.of(context).colorScheme.primaryContainer
                  : null,
            ),
            child: Row(
              children: [
                // Expand/collapse icon
                if (hasChildren)
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: widget.node.isLoading
                        ? const Padding(
                            padding: EdgeInsets.all(4),
                            child: CircularProgressIndicator(strokeWidth: 1.5),
                          )
                        : Icon(
                            widget.node.isExpanded
                                ? Icons.expand_more
                                : Icons.chevron_right,
                            size: 18,
                          ),
                  )
                else
                  const SizedBox(width: 20),
                const SizedBox(width: 4),
                // Folder icon
                Icon(
                  widget.node.isExpanded && hasChildren
                      ? Icons.folder_open
                      : Icons.folder,
                  size: 18,
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).iconTheme.color,
                ),
                const SizedBox(width: 8),
                // Folder name
                Expanded(
                  child: Text(
                    widget.node.name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
        // Children (expanded)
        if (widget.node.isExpanded && widget.node.children.isNotEmpty)
          ...widget.node.children.map(
            (child) => _TreeNodeWidget(node: child, level: widget.level + 1),
          ),
      ],
    );
  }

  void _onTap(BuildContext context) {
    final appState = context.read<AppState>();

    if (!widget.node.isLeaf) {
      // Toggle expand/collapse for non-leaf nodes
      setState(() {
        widget.node.isExpanded = !widget.node.isExpanded;
      });
      // Lazy load children if not loaded yet
      if (widget.node.isExpanded && widget.node.children.isEmpty) {
        appState.loadTreeChildren(widget.node);
      }
    }

    // Select this node and load its contents
    appState.selectTreeNode(widget.node.fullPath);
  }
}

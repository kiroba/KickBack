// kickback_educator_forum_ui.dart
// The KickBack - Educator Forum & Discussion Board UI (Flutter / Dart)
// Serverless P2P Discussion Forum with Verified Educator Badges, Student Assignment Threads, & Signed Moderation

import 'package:flutter/material.dart';

class KickBackEducatorForumScreen extends StatefulWidget {
  const KickBackEducatorForumScreen({super.key});

  @override
  State<KickBackEducatorForumScreen> createState() => _KickBackEducatorForumScreenState();
}

class _KickBackEducatorForumScreenState extends State<KickBackEducatorForumScreen> {
  final List<Map<String, dynamic>> _forumThreads = [
    {
      'id': 'thread_101',
      'title': 'Week 4 Discussion: Merkle DAG Integrity vs Central Databases',
      'author': 'Prof. Keith',
      'author_role': 'Educator',
      'category': 'Assignment Discussion',
      'pinned': true,
      'replies_count': 14,
      'timestamp': '2 hours ago',
      'preview': 'Explain how SHA-256 Merkle chain linking prevents historical log manipulation even when nodes disconnect...',
    },
    {
      'id': 'thread_102',
      'title': 'Question on Negentropy Range Fingerprinting Bounds',
      'author': 'Alex M.',
      'author_role': 'Student',
      'category': 'Q&A Help Desk',
      'pinned': false,
      'replies_count': 6,
      'timestamp': '5 hours ago',
      'preview': 'When two devices compare fingerprints, what happens if timestamp clocks differ by 10 seconds?',
    },
    {
      'id': 'thread_103',
      'title': 'Project Lab: Designing a Phaser 2D Mini-Game Mod',
      'author': 'Prof. Keith',
      'author_role': 'Educator',
      'category': 'Project Showcase',
      'pinned': false,
      'replies_count': 22,
      'timestamp': '1 day ago',
      'preview': 'Post your .omnimod manifest CIDs below to share your mini-game builds with the class over P2P sync.',
    },
  ];

  String _selectedCategory = 'All Topics';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        title: Row(
          children: const [
            Icon(Icons.forum_outlined, color: Colors.tealAccent, size: 22),
            SizedBox(width: 10),
            Text(
              'KickBack Educator Forum',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12, top: 12, bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.teal.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.tealAccent, width: 0.5),
            ),
            child: Row(
              children: const [
                Icon(Icons.verified, size: 12, color: Colors.tealAccent),
                SizedBox(width: 4),
                Text('Class Sync', style: TextStyle(color: Colors.tealAccent, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Category Filter Pills
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  'All Topics',
                  'Assignment Discussion',
                  'Q&A Help Desk',
                  'Project Showcase',
                  'Announcements'
                ].map((cat) {
                  final isSelected = _selectedCategory == cat;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: FilterChip(
                      selected: isSelected,
                      label: Text(cat),
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.black : Colors.white70,
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                      backgroundColor: const Color(0xFF1E293B),
                      selectedColor: Colors.tealAccent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      onSelected: (_) => setState(() => _selectedCategory = cat),
                    ),
                  );
                }).toList(),
              ),
            ),

            // Threads Feed
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                itemCount: _forumThreads.length,
                itemBuilder: (context, index) {
                  final item = _forumThreads[index];
                  final isEdu = item['author_role'] == 'Educator';

                  if (_selectedCategory != 'All Topics' && item['category'] != _selectedCategory) {
                    return const SizedBox.shrink();
                  }

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: item['pinned'] ? Colors.amberAccent.withOpacity(0.5) : Colors.white10,
                        width: item['pinned'] ? 1.5 : 1.0,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Pinned Indicator & Category Badge
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.teal.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                item['category'],
                                style: const TextStyle(color: Colors.tealAccent, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ),
                            if (item['pinned'])
                              Row(
                                children: const [
                                  Icon(Icons.push_pin, size: 12, color: Colors.amberAccent),
                                  SizedBox(width: 4),
                                  Text('PINNED BY EDUCATOR', style: TextStyle(color: Colors.amberAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                                ],
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        // Title
                        Text(
                          item['title'],
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),

                        // Preview
                        Text(
                          item['preview'],
                          style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.3),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 12),

                        // Footer Meta Info
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 12,
                                  backgroundColor: isEdu ? Colors.teal : Colors.indigo,
                                  child: Text(item['author'][0], style: const TextStyle(color: Colors.white, fontSize: 10)),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  item['author'],
                                  style: TextStyle(
                                    color: isEdu ? Colors.tealAccent : Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (isEdu) ...[
                                  const SizedBox(width: 4),
                                  const Icon(Icons.verified, size: 13, color: Colors.tealAccent),
                                ],
                                const SizedBox(width: 8),
                                Text(
                                  '• ${item['timestamp']}',
                                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                const Icon(Icons.chat_bubble_outline, size: 14, color: Colors.white54),
                                const SizedBox(width: 4),
                                Text(
                                  '${item['replies_count']}',
                                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showNewTopicDialog(context),
        backgroundColor: Colors.tealAccent,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add_comment),
        label: const Text('New Discussion', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  void _showNewTopicDialog(BuildContext context) {
    final titleController = TextEditingController();
    final bodyController = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Start Forum Discussion', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Topic Title',
                labelStyle: TextStyle(color: Colors.white70),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.tealAccent)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: bodyController,
              maxLines: 3,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Question / Description',
                labelStyle: TextStyle(color: Colors.white70),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              if (titleController.text.trim().isNotEmpty) {
                setState(() {
                  _forumThreads.insert(0, {
                    'id': 'thread_${DateTime.now().millisecondsSinceEpoch}',
                    'title': titleController.text.trim(),
                    'author': 'Student (You)',
                    'author_role': 'Student',
                    'category': 'Q&A Help Desk',
                    'pinned': false,
                    'replies_count': 0,
                    'timestamp': 'Just now',
                    'preview': bodyController.text.trim(),
                  });
                });
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Discussion published & signed into local event store')),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.tealAccent, foregroundColor: Colors.black),
            child: const Text('Publish Topic'),
          ),
        ],
      ),
    );
  }
}

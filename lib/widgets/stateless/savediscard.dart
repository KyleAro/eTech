import 'package:flutter/material.dart';

class SaveDiscardButtons extends StatelessWidget {
  final bool showButtons;
  final bool hasMadeChoice;
  final VoidCallback onSave;
  final VoidCallback onDiscard;

  const SaveDiscardButtons({
    Key? key,
    required this.showButtons,
    required this.hasMadeChoice,
    required this.onSave,
    required this.onDiscard,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (!showButtons || hasMadeChoice) return const SizedBox.shrink();

    return AnimatedSwitcher(
     

      duration: const Duration(milliseconds: 100),
      transitionBuilder: (child, animation) => SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 2),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: Row(
        
        key: const ValueKey('saveDiscardRow'),
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
           
          // SAVE BUTTON
          ElevatedButton.icon(
            
            onPressed: onSave,
            icon: const Icon(Icons.save, color: Colors.white),
            label: const Text('Save'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color.fromARGB(255, 56, 167, 113),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
            ),
          ),
          const SizedBox(width: 20),

          // DISCARD BUTTON
          ElevatedButton.icon(
            onPressed: onDiscard,
            icon: const Icon(Icons.delete, color: Colors.white),
            label: const Text('Discard'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color.fromARGB(255, 202, 87, 110),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

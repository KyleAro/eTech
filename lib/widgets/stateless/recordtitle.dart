import 'package:flutter/material.dart';

class RecordTitleField extends StatelessWidget {
  final bool showTitleField;
  final TextEditingController titleController;
  // 💡 NEW: Added FocusNode to enable auto-select logic in parent widget
  final FocusNode? titleFocusNode; 

  const RecordTitleField({
    Key? key,
    required this.showTitleField,
    required this.titleController,
    this.titleFocusNode, // FocusNode is now an optional parameter
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    
    // --- Define common border style ---
    const OutlineInputBorder borderStyle = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(12.0)), // Softer rounded corners
      borderSide: BorderSide(color: Colors.white70, width: 1.5),
    );

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300), // Increased duration for a smoother slide
      transitionBuilder: (child, animation) => SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.5), 
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: animation,
          curve: Curves.easeOut,
        )),
        child: FadeTransition(
          opacity: animation,
          child: child,
        ),
      ),
      

      child: showTitleField
          ? Column(
              key: const ValueKey('titleField'),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: TextField(
                    controller: titleController,
                    focusNode: titleFocusNode, // 💡 NEW: Attach the FocusNode
                    textAlign: TextAlign.center,
                    cursorColor: Colors.lightBlueAccent, // Set cursor color
                    style: const TextStyle(color: Colors.white, fontSize: 18),
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 20.0), // Consistent padding
                      labelText: 'Recording Title',
                      labelStyle: const TextStyle(color: Colors.white70),
                      
                      // 💡 NEW STYLE: Rounded borders
                      enabledBorder: borderStyle,
                      focusedBorder: borderStyle.copyWith(
                        borderSide: const BorderSide(color: Colors.lightBlueAccent, width: 2.0),
                      ),
                      
                      // Hint style can be useful if label is removed
                      hintText: 'Enter a title',
                      hintStyle: const TextStyle(color: Colors.grey),
                    ),
                  ),
                ),
                const SizedBox(height: 14.9),
              ],
            )
          : const SizedBox.shrink(),
    );
  }
}
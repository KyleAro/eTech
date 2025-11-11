import 'package:flutter/material.dart';

class RecordTitleField extends StatelessWidget {
  final bool showTitleField;
  final TextEditingController titleController;

  const RecordTitleField({
    Key? key,
    required this.showTitleField,
    required this.titleController,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    const OutlineInputBorder borderStyle = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(12.0)),
      borderSide: BorderSide(color: Colors.white70, width: 1.5),
    );

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
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
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: TextField(
                    controller: titleController,
                    textAlign: TextAlign.center,
                    readOnly: true, // make it non-editable
                    cursorColor: const Color.fromARGB(255, 228, 213, 8),
                    style: const TextStyle(color: Colors.white, fontSize: 18),
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 16.0, horizontal: 20.0),
                      labelText: 'Record Title',
                      labelStyle: const TextStyle(color: Colors.white70),
                      enabledBorder: borderStyle,
                      focusedBorder: borderStyle.copyWith(
                        borderSide: const BorderSide(
                            color: Color.fromARGB(255, 228, 213, 8), width: 2.0),
                      ),
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

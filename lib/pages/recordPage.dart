import 'dart:io';
import 'package:flutter/material.dart';
import '../style/mainpage_style.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import '../widgets/stateless/timer.dart';
import '../widgets/stateless/recordtitle.dart';
import '../widgets/stateless/savediscard.dart';




class RecordPage extends StatefulWidget {
  @override
  _RecordPageState createState() => _RecordPageState();
}

class _RecordPageState extends State<RecordPage> {

  // CONTROLLERS

  final recorder = FlutterSoundRecorder();
  TextEditingController titleController = TextEditingController();


 


  // BOOLEANS
  bool showTitleField = false;
  bool isRecorderReady = false;
  bool isRecording = false;
  bool isPlaying = false;
  bool isPressed = false;
  bool hasmadeChoice = false;
  String? filePath;







// ───────── STATE TOGGLES ─────────
void toggleisPressed() {
    setState(() {
      isPressed = !isPressed;
    });
  }


// ───────── LIFECYCLE ─────────
@override
void initState() {
  super.initState();
  initRecorder();


}


@override
void dispose() {
  recorder.closeRecorder
  
  ();
  super.dispose();
}

// delete file


Future<void> deleteFile(String filePath) async {
  try {
    final file = File(filePath);

    if (await file.exists()) {
      await file.delete();
      print('File deleted successfully!');
    } else {
      print('File does not exist.');
    }
  } catch (e) {
    print('Error deleting file: $e');
  }
}
// ───────── FILE PATH HELPER ─────────
// to get the file path nung pagsesavean
// ───────── FILE PATH HELPER ─────────
// to get the file path nung pagsesavean
Future<String> getFilePath() async {
    final directory = await getExternalStorageDirectory();

    // Use a local counter to check for the next available number
    int count = 1;
    String uniquePath = '';

    // Loop until a non-existent file path is found
    while (true) {
      uniquePath = '${directory!.path}/Recording_$count.aac';

      // Check if the file already exists
      if (!await File(uniquePath).exists()) {
        break; // Found a unique path!
      }
      count++;
    }
    // Returns the first path that was found NOT to exist
    return uniquePath;
  }

// ───────── INITIALIZE RECORDER ─────────
// this is para sa permission to access the audio recorder

Future initRecorder() async {
  final status = await Permission.microphone.request();
  if (status != PermissionStatus.granted) {
    // the print is for debugging purposes
   // print("Status: $status");
    throw 'Microphone permission not granted';
    
  }
  await recorder.openRecorder();
  isRecorderReady = true;
  

  recorder.setSubscriptionDuration(const Duration(milliseconds: 500));

// debug purposes para makita kung naandar yung stream
  //print("Setting up onProgress listener...");
//recorder.onProgress?.listen((event) {
  //print("Progress: ${event.duration}");

//});
}

// ───────── RECORD FUNCTION ─────────
// eto para sa record function

Future record() async {
    if (!isRecorderReady) return;
    if (filePath != null) {
      print("Error: A recording is already stopped and awaiting save/discard.");
      // Optionally show a SnackBar to the user here
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please save or discard the current recording first.')),
      );
      return; 
  }

    filePath = await getFilePath();

    
    final fileName = filePath!.split('/').last;
    titleController.text = fileName.split('.').first; 

      await recorder.startRecorder(toFile: filePath);
      setState(() {
        showTitleField = true; 
        hasmadeChoice = false;
        isRecording = true;
      });

    await recorder.startRecorder(toFile: filePath);
    setState(() {
      showTitleField = true;
      hasmadeChoice = false;
      isRecording = true;
    });
  }

// ───────── STOP FUNCTION ─────────
// eto para sa stop function

Future stop() async {
  if (!isRecorderReady) return;
        await recorder.stopRecorder();
setState(() {
      isRecording = false;  
    });

}

// ───────── SAVE FUNCTION ─────────
// this to save recording

Future<void> saveRecording() async {
  if (filePath == null || hasmadeChoice) return;

 // title place holder muna
 
 
  String rawTitle = titleController.text.trim();
  String defaultName = filePath!.split('/').last.split('.').first;
  String finalTitle = rawTitle.isNotEmpty ? rawTitle : defaultName;


  String recordTitle = finalTitle.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');

  if (recordTitle.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Please enter a valid file name.')),
    );
    return;
  }

  // Eto yung mapupuntahan nung file na sasasve 
  final directory = await getExternalStorageDirectory();
  String finalSavePath = '${directory!.path}/$recordTitle.aac';
  File tempFile = File(filePath!);
  File saveFile = File(finalSavePath);


  // pang overwrite lang pag existing na yung fileee
  if (finalSavePath != filePath && await saveFile.exists()) {
    final overwrite = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Overwrite File?'),
        content: Text('A file named "$recordTitle.aac" already exists. Overwrite?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Overwrite', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (overwrite != true) {
      return;
    }
  }
  try {
    
    if (await saveFile.exists() && finalSavePath != filePath) {
      await saveFile.delete();
    }
    
    await tempFile.rename(finalSavePath);

    // 5. Update the state
    setState(() {
      hasmadeChoice = true;
      filePath = null;
      showTitleField = false;
      titleController.clear();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Recording saved as "$recordTitle.aac"')),
    );

  } catch (e) {
    print('Critical save error: $e');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('🚨 Failed to save file! Error: $e')),
    );
  }
}

  
// ───────── DISCARD FUNCTION ─────────
// para sa discard naman boi

Future<void> discardRecording() async {
  if (filePath == null || hasmadeChoice) return;

  final file = File(filePath!);
  if (await file.exists()) {
    await file.delete();
  }

  setState(() {
    filePath = null;
    hasmadeChoice = true;
    showTitleField = false;
    titleController.clear();
  });

  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Recording discarded')),
  );

}
  // TODO: Move or upload the recorded file to your desired location

 // ======================================================
  // 🔹 TODO: ADD YOUR EXTRA FUNCTIONS HERE
  // ======================================================
  // Example:
  // Future<void> pauseRecording() async { ... }
  // Future<void> resumeRecording() async { ... }
  // Future<void> playRecording() async { ... }




// ───────── BUILD UI ─────────
@override
  Widget build(BuildContext context) {
    
    return Scaffold(

      // ───── BODY ─────
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          
          children: [
            
            // =========================================
            // 🏷️ FILE TITLE DISPLAY & EDIT FIELD
            // =========================================
              RecordTitleField(
                    showTitleField: showTitleField,
                    titleController: titleController,
                  ),


            // =========================================
            // 🏷️ TIMER DISPLAY
            // =========================================
               RecordTimer(
                      isRecording: isRecording,
                      progressStream: recorder.onProgress,
                    ),

                            
                  // =========================================
                  // 🏷️ RECORD / STOP
                  // =========================================

                    // this is the neu box button for record and stop 
                    //this is command when you push the button

                     GestureDetector(
                      // explanation
                      // isRecording = false, when i put if not isRecording
                          onTap: () async {
                            if (!isRecording) {
                              await record();
                              print("Started Recording");
                              print("Am i Recording: ${!isRecording}");
                              print('Recording to: $filePath');
                              
                            } else {
                              await stop();
                              print("Stopped Recording");
                              print("Am i Recording: ${!isRecording}");
                              print('Recording to: $filePath');}
              // ── STATE UPDATE AFTER TAP ──

              // so double negative the init state of ispressed == ! is pressed so false to true 
              //then after it is clicked again it will be true to false 
                              setState(() {
                                isPressed = !isPressed;

                                // Debug prints
                                print('isPressed: $isPressed');
                                print('isRecording: $isRecording');
                              });
                            },

           // ───────── NEUMORPHIC RECORD BUTTON CONTAINER ─────────
          // 🎤 Record Button with smooth move-down animation
                child: AnimatedPadding(
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeInOut,
                    padding: EdgeInsets.only(top: isRecording ? 80 : 0), // moves down when recording
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      height: 200,
                      width: 200,
                      child: NeuBox(
                        isPressed: isPressed,
                        child: Icon(
                          isPressed ? Icons.stop : Icons.mic,
                          size: 100,
                          color: const Color.fromARGB(255, 0, 0, 0),

                        ),
                        
                      ),
                      
                    ),
                  ),
                  
                ),const SizedBox(height: 20,),
        // =========================================
        // 🏷️ SAVE / DISCARD BUTTONS
        // =========================================

            SaveDiscardButtons(
              
                  showButtons: !isRecording && filePath != null,
                  hasMadeChoice: hasmadeChoice,
                  onSave: saveRecording,
                  onDiscard: discardRecording,
                ),


    
      // ───────── (PLACEHOLDER FOR FUTURE FEATURES) ─────────
         // Here’s where you can later add:
            // - Play / Pause preview buttons
            // - Save / Discard buttons
            // - Upload status indicators

          ],
    ),

      ),

    );
  
  }
}
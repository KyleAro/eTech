
import 'package:flutter/material.dart';
import '../style/mainpage_style.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';




class RecordPage extends StatefulWidget {
  @override
  _RecordPageState createState() => _RecordPageState();
}

class _RecordPageState extends State<RecordPage> {
  final recorder = FlutterSoundRecorder();
  bool isRecorderReady = false;
  bool isRecording = false;
  bool isPlaying = false;
  bool isPressed = false;
  String? filePath;


void toggleisPressed() {
    setState(() {
      isPressed = !isPressed;
    });
  }



@override
void initState() {
  super.initState();
  initRecorder();
}

@override
void dispose() {
  recorder.closeRecorder();
  super.dispose();
}
  Future<String> getFilePath() async {
    // papaltan to  ng either applicationdocuments or externalStorage
    final directory = await getExternalStorageDirectory();
    // papaltan ng directory!.path(kapag external) to directory.path(applicationdocuments)
    final path = '${directory!.path}/audio_${DateTime.now().millisecondsSinceEpoch}.aac';
    return path;
  }
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
// eto para sa record function
Future record() async {
  if (!isRecorderReady) return;  // Check if the recorder is ready
  filePath = await getFilePath();  
    await recorder.startRecorder(toFile: filePath);
  
}


// eto para sa stop function


Future stop() async {
  if (!isRecorderReady) return;
        await recorder.stopRecorder();
setState(() {
      isRecording = false;  // Update the state to reflect that recording has stopped
    });

}
@override
  Widget build(BuildContext context) {
    
    return Scaffold(
      
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          
          children: [
            
                StreamBuilder<RecordingDisposition>(
            stream: recorder.onProgress,
            builder: (context, snapshot) {
              final duration = snapshot.hasData
                  ?  snapshot.data!.duration
                  : Duration.zero;


                  // shows the 00:00 format for the duration
                  String twoDigits(int n) => n.toString().padLeft(2, '0');
                  final twoDigitMinutes = 
                    twoDigits(duration.inMinutes.remainder(60));
                  final twoDigitSeconds = 
                    twoDigits(duration.inSeconds.remainder(60));
              
                  return Text(
                    '$twoDigitMinutes : $twoDigitSeconds',
                    style: getTitleTextStyle(context).copyWith
                    (
                      fontSize: 48,
                      color: const Color.fromARGB(255, 255, 255, 255),
                   
                    ),
                    

                    );
                    
                    
            },
            
                ),
                // this is the neu box button for record and stop 
                //this is command when you push the button
                    const SizedBox(height: 40),
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
                              print('Recording to: $filePath');
                              
                  
                }
              // so double negative the init state of ispressed == ! is pressed so false to true 
              //then after it is clicked again it will be true to false 
              setState(() {
                isPressed = !isPressed;
                isRecording = !isRecording;

                // Debug prints
                print('isPressed: $isPressed');
                print('isRecording: $isRecording');
              });
            },

         
          child: AnimatedContainer(
            
            duration: const Duration(milliseconds: 100),
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
          ],
    ),

      ),

    );
  
  }
}
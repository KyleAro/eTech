import 'package:etech/style/mainpage_style.dart';
import 'package:flutter/material.dart';
import 'MainPage.dart';

class Upload extends StatefulWidget {
  @override
  _UploadState createState() => _UploadState();
}

class _UploadState extends State<Upload> {
  List<Item> _items = <Item>[
    Item(header: 'Audio File 1', body: 'Details about Audio File 1'),
    Item(header: 'Audio File 2', body: 'Details about Audio File 2'),
    Item(header: 'Audio File 3', body: 'Details about Audio File 3'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: backgroundColor,
        title: Text(
          'Upload Page',
          style: getTitleTextStyle(context).copyWith(
            fontSize: 25,
            color: Colors.white,
          ),
        ),
      ),
      body: SingleChildScrollView(
        child: Container(
          padding: const EdgeInsets.all(16.0),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionPanelList(
              elevation: 1,
              expandedHeaderPadding: EdgeInsets.symmetric(vertical: 5),
              animationDuration: const Duration(milliseconds: 300),
              expansionCallback: (int index, bool isExpanded) {
                setState(() {
                  _items[index].isExpanded = isExpanded;
                });
              },
              children: _items.map<ExpansionPanel>((Item item) {
                return ExpansionPanel(
                  canTapOnHeader: true, 
                  backgroundColor: Colors.grey[900],
                  headerBuilder: (BuildContext context, bool isExpanded) {
                    return ListTile(
                      title: Text(
                        item.header,
                        style: const TextStyle(color: Colors.white),
                      ),
                    );
                  },
                  body: Container(
                    padding: const EdgeInsets.all(12.0),
                    color: Colors.grey[850],
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            item.body,
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.redAccent),
                          onPressed: () {
                            setState(() {
                              _items.remove(item);
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                  isExpanded: item.isExpanded,
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }
}

class Item {
  String header;
  String body;
  bool isExpanded;

  Item({
    required this.header,
    required this.body,
    this.isExpanded = false,
  });
}

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:download/download.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:random_face_generator/constants.dart';
import 'package:random_face_generator/custom_theme.dart';
import 'package:random_face_generator/face.dart';
import 'package:random_face_generator/neumorphic_elevated_button.dart';
import 'package:random_face_generator/neumorphic_icon_button.dart';
import 'package:random_face_generator/neumorphic_radio_button.dart';

late Uint8List initialImageList;
void main() async {
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(statusBarColor: Colors.transparent),
  );
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  await initializeApp();
  FlutterNativeSplash.remove();
  runApp(
    const MaterialApp(
      home: Home(),
      debugShowCheckedModeBanner: false,
    ),
  );
}

Future initializeApp() async {
  await Hive.initFlutter();
  await Hive.openBox(kHiveSystemPrefs);
  String _initialUrl = kInitialUrl;
  if (kIsWeb) _initialUrl = kCorsProxyUrl + kInitialUrl;
  initialImageList = await http.readBytes(Uri.parse(_initialUrl));
}

class Home extends StatefulWidget {
  const Home({Key? key}) : super(key: key);

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int _minimumAge = 0, _maximumAge = 100, _selectedIndex = 2;
  late String queryUrl, imageUrl;
  Uint8List imageList = initialImageList;
  bool _loading = false;
  CustomTheme customTheme = CustomTheme();
  @override
  void initState() {
    queryUrl = kDefaultUrl;
    imageUrl = kInitialUrl;
    if (kIsWeb) imageUrl = kCorsProxyUrl + imageUrl;
    super.initState();
    customTheme.addListener(() {
      setState(() {});
    });
  }

  void _setMale() {
    setState(() {
      _selectedIndex = 0;
    });
  }

  void _setFemale() {
    setState(() {
      _selectedIndex = 1;
    });
  }

  void _setRandom() {
    setState(() {
      _selectedIndex = 2;
    });
  }

  void _setAgeRange(RangeValues range) {
    setState(() {
      _minimumAge = range.start.floor();
      _maximumAge = range.end.floor();
    });
  }

  void _setGenderQuery() {
    switch (_selectedIndex) {
      case 0:
        queryUrl = kDefaultUrl + "?gender=male";
        break;
      case 1:
        queryUrl = kDefaultUrl + "?gender=female";
        break;
      case 2:
        queryUrl = kDefaultUrl;
        break;
    }
  }

  void _setAgeQuery() {
    if (_selectedIndex != 2) {
      if (_minimumAge != 0) {
        queryUrl += "&minimum_age=$_minimumAge";
      }
      if (_maximumAge != 100) {
        queryUrl += "&maximum_age=$_maximumAge";
      }
    } else {
      if (_minimumAge != 0) {
        queryUrl += "?minimum_age=$_minimumAge";
        if (_maximumAge != 100) {
          queryUrl += "&maximum_age=$_maximumAge";
        }
      } else if (_maximumAge != 100) {
        queryUrl += "?maximum_age=$_maximumAge";
      }
    }
  }

  Future _displayErrorAlert(String title, String content) {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  Future _fetchImage() async {
    _setGenderQuery();
    _setAgeQuery();
    setState(() {
      _loading = true;
    });
    try {
      if (queryUrl == kDefaultUrl) {
        imageUrl = kInitialUrl;
      } else {
        if (kIsWeb) queryUrl = kCorsProxyUrl + queryUrl;
        final response = await http.get(Uri.parse(queryUrl));
        imageUrl = Face.fromJson(jsonDecode(response.body)).imageUrl;
      }
      if (kIsWeb) imageUrl = kCorsProxyUrl + imageUrl;
      imageList = await http.readBytes(Uri.parse(imageUrl));
    } catch (e) {
      if (e.runtimeType == SocketException) {
        _displayErrorAlert(
          "Network Error",
          "Unable to connect to the internet. Please check your internet connection and try again.",
        );
      } else if (e.runtimeType == FormatException) {
        _displayErrorAlert(
          "Invalid Range",
          "Unable to generate a face in this age range. Please try again with a different range.",
        );
      } else {
        _displayErrorAlert(
          "Unknown Error Occurred",
          "Please Try again Later.",
        );
      }
      return;
    }
    setState(() {
      _loading = false;
    });
  }

  Future<String> getDestinationPathName(String pathName,
      {bool isAndroid = true}) async {
    String destinationPath =
        pathName + "${isAndroid ? "/" : "\\"}randomface.png";
    int i = 1;
    bool _isFileExists = await File(destinationPath).exists();
    while (_isFileExists) {
      _isFileExists =
          await File(pathName + "${isAndroid ? "/" : "\\"}randomface($i).png")
              .exists();
      if (_isFileExists == false) {
        destinationPath =
            pathName + "${isAndroid ? "/" : "\\"}randomface($i).png";
        break;
      }
      i++;
    }
    return destinationPath;
  }

  Future _downloadImage() async {
    if (_loading) return;
    Directory? appDir;
    final stream = Stream.fromIterable(imageList);
    if (kIsWeb) {
      await download(stream, "randomface.png");
      return;
    } else if (Platform.isAndroid) {
      appDir = await getExternalStorageDirectory();
    } else {
      appDir = await getDownloadsDirectory();
    }
    String pathName = appDir?.path ?? "";
    String destinationPath =
        await getDestinationPathName(pathName, isAndroid: Platform.isAndroid);
    await download(stream, destinationPath);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          "The image has been downloaded successfully to $destinationPath",
          style: const TextStyle(color: kRegentGray),
        ),
        duration: const Duration(seconds: 5),
        backgroundColor: customTheme.snackBarColor,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _imageView() {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: customTheme.boxDecoration.copyWith(
          borderRadius: BorderRadius.circular(8),
        ),
        child: (_loading)
            ? const FittedBox(
                fit: BoxFit.none,
                child: CircularProgressIndicator(color: kRegentGray),
              )
            : ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(imageList),
              ),
      ),
    );
  }

  Widget _buildSlider() {
    return Container(
      height: 60,
      padding: const EdgeInsets.all(8),
      decoration: customTheme.boxDecoration.copyWith(
        border: customTheme.border,
      ),
      child: Row(
        children: [
          Text(
            "$_minimumAge yrs",
            style: const TextStyle(fontSize: 14, color: kRegentGray),
          ),
          if (_minimumAge < 10)
            Text(
              "0",
              style:
                  TextStyle(fontSize: 14, color: customTheme.backgroundColor),
            ),
          Flexible(
            child: RangeSlider(
              values: RangeValues(
                _minimumAge.toDouble(),
                _maximumAge.toDouble(),
              ),
              min: 0,
              max: 100,
              activeColor: kRegentGray,
              inactiveColor: customTheme.shadowColor,
              onChanged: _setAgeRange,
            ),
          ),
          if (_maximumAge < 10)
            Text(
              "0",
              style:
                  TextStyle(fontSize: 14, color: customTheme.backgroundColor),
            ),
          Text(
            "$_maximumAge yrs",
            style: const TextStyle(fontSize: 14, color: kRegentGray),
          ),
        ],
      ),
    );
  }

  Widget _optionsView() {
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Container(
            height: 60,
            decoration: customTheme.boxDecoration,
            child: Row(
              children: [
                Flexible(
                  child: NeumorphicRadioButton(
                    onTap: _setMale,
                    isSelected: (_selectedIndex == 0),
                    icon: Icons.male,
                  ),
                ),
                Flexible(
                  child: NeumorphicRadioButton(
                    onTap: _setFemale,
                    isSelected: (_selectedIndex == 1),
                    icon: Icons.female,
                  ),
                ),
                Flexible(
                  child: NeumorphicRadioButton(
                    onTap: _setRandom,
                    isSelected: (_selectedIndex == 2),
                    icon: Icons.shuffle,
                  ),
                ),
              ],
            ),
          ),
          _buildSlider(),
          Row(
            children: [
              Expanded(
                flex: 5,
                child: NeumorphicElevatedButton(
                  child: const Text(
                    "Generate",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: kRegentGray,
                    ),
                  ),
                  onTap: _fetchImage,
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: NeumorphicElevatedButton(
                  child: const Icon(Icons.download, color: kLimeGreen),
                  onTap: _downloadImage,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: customTheme.backgroundColor,
      appBar: AppBar(
        backgroundColor: customTheme.backgroundColor,
        elevation: 0,
        title: Text(
          "Random Face Generator",
          style: TextStyle(
            fontWeight: FontWeight.w600,
            shadows: customTheme.boxShadows,
            color: kRegentGray,
          ),
        ),
        actions: [
          NeumorphicIconButton(
            icon: customTheme.icon,
            onTap: () {
              customTheme.switchTheme();
            },
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth > 700 ||
              constraints.maxWidth > constraints.maxHeight) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  _imageView(),
                  const SizedBox(width: 30),
                  _optionsView(),
                ],
              ),
            );
          } else {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
              child: Column(
                children: [
                  _imageView(),
                  _optionsView(),
                ],
              ),
            );
          }
        },
      ),
    );
  }
}
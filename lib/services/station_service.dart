import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/station_model.dart'; // This imports the model you created earlier!

class StationService {
  // This function reads your JSON file and turns it into a list of Station objects
  static Future<List<Station>> loadStations() async {
    
    // 1. Load the raw text from the file we registered in pubspec.yaml
    final String response = await rootBundle.loadString('assets/data/stations.json');
    
    // 2. Convert that raw text into a format Dart can read (a Map)
    final data = await jsonDecode(response);
    
    // 3. Extract just the list of stations from the "featured_stations" section
    var stationList = data['data']['featured_stations'] as List;
    
    // 4. Translate each item in that list using our Station model
    return stationList.map((stationJson) => Station.fromJson(stationJson)).toList();
  }
}
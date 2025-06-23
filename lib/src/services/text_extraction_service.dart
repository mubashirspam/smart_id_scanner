import 'dart:developer' as dev;
import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:intl/intl.dart';

enum TextExtractionLanguage {
  latin,
  chinese,
  devanagiri,
  japanese,
  korean,
}

enum ExtractedDataType { date, number, string }

class ExtractedDataModel {
  final String key;
  final ExtractedDataType type;
  
  ExtractedDataModel({
    required this.key,
    required this.type,
  });
}

class ExtractedFieldResult {
  final String key;
  final String? value;
  final ExtractedDataType type;
  final bool found;
  
  ExtractedFieldResult({
    required this.key,
    required this.value,
    required this.type,
    required this.found,
  });
  
  @override
  String toString() {
    return 'ExtractedFieldResult(key: $key, value: $value, type: $type, found: $found)';
  }
}

class TextExtractionService {
  TextRecognizer? _textRecognizer;
  
  TextExtractionService({
    TextExtractionLanguage language = TextExtractionLanguage.latin,
  }) {
    _initializeRecognizer(language);
  }
  
  void _initializeRecognizer(TextExtractionLanguage language) {
    final script = _getTextRecognitionScript(language);
    _textRecognizer = TextRecognizer(script: script);
  }
  
  TextRecognitionScript _getTextRecognitionScript(TextExtractionLanguage language) {
    switch (language) {
      case TextExtractionLanguage.latin:
        return TextRecognitionScript.latin;
      case TextExtractionLanguage.chinese:
        return TextRecognitionScript.chinese;
      case TextExtractionLanguage.devanagiri:
        return TextRecognitionScript.devanagiri;
      case TextExtractionLanguage.japanese:
        return TextRecognitionScript.japanese;
      case TextExtractionLanguage.korean:
        return TextRecognitionScript.korean;
    }
  }

  Future<ExtractedTextData> extractText(File imageFile) async {
    if (_textRecognizer == null) {
      throw Exception('Text recognizer not initialized');
    }

    try {
      final inputImage = InputImage.fromFilePath(imageFile.path);
      final recognizedText = await _textRecognizer!.processImage(inputImage);
      
      final extractedData = ExtractedTextData(
        fullText: recognizedText.text,
        textLines: recognizedText.text.split('\n'),
        blocks: recognizedText.blocks.map((block) => TextBlockData(
          text: block.text,
          boundingBox: block.boundingBox,
          confidence: 1,
        )).toList(),
      );
      
      dev.log('Extracted text: ${recognizedText.text}', name: 'TextExtraction');
      
      return extractedData;
    } catch (e) {
      dev.log('Error extracting text: $e', name: 'TextExtraction');
      rethrow;
    }
  }

  Future<bool> validateDocumentType(File imageFile, List<String> keywords) async {
    try {
      final extractedData = await extractText(imageFile);
      final lowerText = extractedData.fullText.toLowerCase();
      
      int matchCount = 0;
      for (final keyword in keywords) {
        if (lowerText.contains(keyword.toLowerCase())) {
          matchCount++;
          dev.log('Found keyword: $keyword', name: 'DocumentValidation');
        }
      }
      
      return matchCount >= (keywords.length * 0.4); // At least 40% match
    } catch (e) {
      dev.log('Error validating document type: $e', name: 'DocumentValidation');
      return false;
    }
  }

  Future<List<ExtractedFieldResult>> extractSpecificFields(
    File imageFile, 
    List<ExtractedDataModel> fieldsToExtract
  ) async {
    final extractedData = await extractText(imageFile);
    final results = <ExtractedFieldResult>[];
    
    for (final field in fieldsToExtract) {
      String? extractedValue;
      bool found = false;
      
      switch (field.type) {
        case ExtractedDataType.date:
          extractedValue = _extractDateField(extractedData, field.key);
          break;
        case ExtractedDataType.number:
          extractedValue = _extractNumberField(extractedData, field.key);
          break;
        case ExtractedDataType.string:
          extractedValue = _extractStringField(extractedData, field.key);
          break;
      }
      
      found = extractedValue != null && extractedValue.isNotEmpty;
      
      results.add(ExtractedFieldResult(
        key: field.key,
        value: extractedValue,
        type: field.type,
        found: found,
      ));
    }
    
    return results;
  }

  String? _extractDateField(ExtractedTextData data, String fieldKey) {
    final labelPattern = RegExp(
      '${RegExp.escape(fieldKey)}\\s*[:\\-]?\\s*([0-9/\\-\\s]+)',
      caseSensitive: false,
    );
    
    final match = labelPattern.firstMatch(data.fullText);
    if (match != null) {
      final dateText = match.group(1)?.trim();
      if (dateText != null && TextProcessingUtils.isValidDate(dateText)) {
        return dateText;
      }
    }
    
    final dates = data.extractDates();
    if (dates.isNotEmpty) {
      final sortedDates = TextProcessingUtils.sortDateList(dates);
      if (fieldKey.toLowerCase().contains('expiry') || 
          fieldKey.toLowerCase().contains('expire')) {
        return sortedDates.last;
      }
      else if (fieldKey.toLowerCase().contains('birth')) {
        return sortedDates.first;
      }
      return sortedDates.first;
    }
    
    return null;
  }

  String? _extractNumberField(ExtractedTextData data, String fieldKey) {
    final labelPattern = RegExp(
      '${RegExp.escape(fieldKey)}\\s*[:\\-]?\\s*([0-9A-Z]+)',
      caseSensitive: false,
    );
    
    final match = labelPattern.firstMatch(data.fullText);
    if (match != null) {
      return match.group(1)?.trim();
    }
    
    if (fieldKey.toLowerCase().contains('civil')) {
      return _findCivilNumber(data);
    } else if (fieldKey.toLowerCase().contains('license')) {
      return _findLicenseNumber(data);
    }
    
    final numbers = data.extractNumbers();
    return numbers.isNotEmpty ? numbers.first : null;
  }

  String? _extractStringField(ExtractedTextData data, String fieldKey) {
    final labelPattern = RegExp(
      '${RegExp.escape(fieldKey)}\\s*[:\\-]?\\s*([^\\n]+)',
      caseSensitive: false,
    );
    
    final match = labelPattern.firstMatch(data.fullText);
    if (match != null) {
      return TextProcessingUtils.cleanText(match.group(1));
    }
    
    if (fieldKey.toLowerCase().contains('name')) {
      final allCapsText = data.extractAllCapsText();
      final filteredNames = allCapsText.where((text) =>
          !text.toLowerCase().contains('oman') &&
          !text.toLowerCase().contains('police') &&
          !text.toLowerCase().contains('sultanate') &&
          text.length > 2
      ).toList();
      
      if (filteredNames.isNotEmpty) {
        return TextProcessingUtils.cleanText(filteredNames.first);
      }
    }
    
    return null;
  }

  String? _findCivilNumber(ExtractedTextData data) {
    final patterns = [
      RegExp(r'civil\s*number[:\s]*(\d{7,8})', caseSensitive: false),
      RegExp(r'(\d{7,8})'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(data.fullText);
      if (match != null && match.group(1) != null) {
        final number = match.group(1)!;
        if (number.length >= 7 && number.length <= 8) {
          return number;
        }
      }
    }

    final numbers = data.extractNumbers();
    for (final number in numbers) {
      if (number.length >= 7 && number.length <= 8) {
        return number;
      }
    }

    return null;
  }

  String? _findLicenseNumber(ExtractedTextData data) {
    final patterns = [
      RegExp(r'license\s*(?:no|number)[:\s]*([A-Z0-9]+)', caseSensitive: false),
      RegExp(r'licence\s*(?:no|number)[:\s]*([A-Z0-9]+)', caseSensitive: false),
      RegExp(r'([A-Z]\d{6,8})'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(data.fullText);
      if (match != null && match.group(1) != null) {
        final number = match.group(1)!;
        if (number.length >= 6) {
          return number;
        }
      }
    }

    return null;
  }

  void dispose() {
    _textRecognizer?.close();
    _textRecognizer = null;
  }
}

class ExtractedTextData {
  final String fullText;
  final List<String> textLines;
  final List<TextBlockData> blocks;
  
  ExtractedTextData({
    required this.fullText,
    required this.textLines,
    required this.blocks,
  });
  
  List<String> extractDates() {
    final datePatterns = [
      RegExp(r'\b\d{1,2}[/\-]\d{1,2}[/\-]\d{2,4}\b'),
      RegExp(r'\b\d{1,2}\s+(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+\d{4}\b', caseSensitive: false),
    ];
    
    final dates = <String>[];
    for (final pattern in datePatterns) {
      final matches = pattern.allMatches(fullText);
      for (final match in matches) {
        if (match.group(0) != null) {
          dates.add(match.group(0)!);
        }
      }
    }
    
    return dates;
  }
  
  List<String> extractNumbers() {
    final numberPattern = RegExp(r'\b\d{6,}\b');
    final matches = numberPattern.allMatches(fullText);
    
    return matches.map((match) => match.group(0)!).toList();
  }
  
  String? extractFieldByLabel(String label, {bool caseSensitive = false}) {
    final pattern = RegExp(
      '$label\\s*[:\\-]\\s*([^\\n]+)',
      caseSensitive: caseSensitive,
    );
    
    final match = pattern.firstMatch(fullText);
    return match?.group(1)?.trim();
  }
  
  List<String> extractAllCapsText() {
    return textLines
        .where((line) => line.trim().isNotEmpty)
        .where((line) => line == line.toUpperCase())
        .where((line) => line.length > 2)
        .map((line) => line.trim())
        .toList();
  }
}

class TextBlockData {
  final String text;
  final dynamic boundingBox;
  final double? confidence;
  
  TextBlockData({
    required this.text,
    required this.boundingBox,
    this.confidence,
  });
}

class TextProcessingUtils {
  static List<String> sortDateList(List<String> dates) {
    if (dates.isEmpty) return dates;
    
    final tempList = <DateTime>[];
    final possibleFormats = [
      DateFormat("dd/MM/yyyy"),
      DateFormat("dd-MM-yyyy"),
      DateFormat("d/M/yyyy"),
      DateFormat("dd MMM yyyy"),
    ];
    
    for (final date in dates) {
      DateTime? parsedDate;
      for (final format in possibleFormats) {
        try {
          parsedDate = format.parse(date);
          break;
        } catch (_) {
          // Try next format
        }
      }
      if (parsedDate != null) {
        tempList.add(parsedDate);
      }
    }
    
    tempList.sort((a, b) => a.compareTo(b));
    
    final sortedDates = <String>[];
    final outputFormat = DateFormat("dd/MM/yyyy");
    for (final date in tempList) {
      sortedDates.add(outputFormat.format(date));
    }
    
    return sortedDates;
  }
  
  static bool isValidDate(String text) {
    final datePatterns = [
      RegExp(r'^\d{2}/\d{2}/\d{4}$'),
      RegExp(r'^\d{2}-\d{2}-\d{4}$'),
      RegExp(r'^\d{1,2}/\d{1,2}/\d{4}$'),
    ];
    
    return datePatterns.any((pattern) => pattern.hasMatch(text));
  }
  
  static String? cleanText(String? text) {
    if (text == null) return null;
    return text.trim().replaceAll(RegExp(r'\s+'), ' ');
  }
  
  static bool containsArabicText(String text) {
    return RegExp(r'[\u0600-\u06FF]').hasMatch(text);
  }
  
  static String removeArabicText(String text) {
    return text.replaceAll(RegExp(r'[\u0600-\u06FF\s]+'), ' ').trim();
  }
}
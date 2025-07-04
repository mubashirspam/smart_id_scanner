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

enum ExtractedDataType { date, number, string, id }

class ExtractedDataModel {
  final String key;
  final ExtractedDataType type;
  final String? dateFormat; // Expected output format like "dd/MM/yyyy"
  final String?
      dateReadingFormat; // Expected input format for better parsing (e.g., "dd/MM/yyyy" or "yyyy/MM/dd")
  final int? minLength; // Minimum length for numbers/IDs
  final int? maxLength; // Maximum length for numbers/IDs
  final List<String>? alternativeKeys; // Alternative field names

  ExtractedDataModel({
    required this.key,
    required this.type,
    this.dateFormat,
    this.dateReadingFormat, // New field for input format
    this.minLength,
    this.maxLength,
    this.alternativeKeys,
  });
}

class ExtractedFieldResult {
  final String key;
  final String? value;
  final ExtractedDataType type;
  final bool found;
  final double confidence; // Confidence score 0-1

  ExtractedFieldResult({
    required this.key,
    required this.value,
    required this.type,
    required this.found,
    this.confidence = 0.0,
  });

  @override
  String toString() {
    return 'ExtractedFieldResult(key: $key, value: $value, type: $type, found: $found, confidence: $confidence)';
  }
}

class TextExtractionService {
  TextRecognizer? _textRecognizer;

  // Instance-level date tracking to avoid reusing dates
  final Map<String, Set<String>> _usedDatesPerDocument = {};

  TextExtractionService({
    TextExtractionLanguage language = TextExtractionLanguage.latin,
  }) {
    _initializeRecognizer(language);
  }

  void _initializeRecognizer(TextExtractionLanguage language) {
    final script = _getTextRecognitionScript(language);
    _textRecognizer = TextRecognizer(script: script);
  }

  TextRecognitionScript _getTextRecognitionScript(
      TextExtractionLanguage language) {
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
        blocks: recognizedText.blocks
            .map((block) => TextBlockData(
                  text: block.text,
                  boundingBox: block.boundingBox,
                  confidence: 1,
                ))
            .toList(),
      );

      dev.log('Extracted text: ${recognizedText.text}', name: 'TextExtraction');

      return extractedData;
    } catch (e) {
      dev.log('Error extracting text: $e', name: 'TextExtraction');
      rethrow;
    }
  }

  Future<bool> validateDocumentType(
      File imageFile, List<String> keywords) async {
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
      File imageFile, List<ExtractedDataModel> fieldsToExtract) async {
    final extractedData = await extractText(imageFile);
    final results = <ExtractedFieldResult>[];

    // Reset used dates for this document
    final documentId = imageFile.path;
    _usedDatesPerDocument[documentId] = {};

    for (final field in fieldsToExtract) {
      String? extractedValue;
      bool found = false;
      double confidence = 0.0;

      switch (field.type) {
        case ExtractedDataType.date:
          final result = _extractDateField(extractedData, field, documentId);
          extractedValue = result['value'];
          confidence = result['confidence'] ?? 0.0;
          break;
        case ExtractedDataType.number:
        case ExtractedDataType.id:
          final result = _extractNumberField(extractedData, field);
          extractedValue = result['value'];
          confidence = result['confidence'] ?? 0.0;
          break;
        case ExtractedDataType.string:
          final result = _extractStringField(extractedData, field);
          extractedValue = result['value'];
          confidence = result['confidence'] ?? 0.0;
          break;
      }

      found = extractedValue != null && extractedValue.isNotEmpty;

      results.add(ExtractedFieldResult(
        key: field.key,
        value: extractedValue,
        type: field.type,
        found: found,
        confidence: confidence,
      ));

      dev.log(
          'Field: ${field.key}, Value: $extractedValue, Found: $found, Confidence: $confidence',
          name: 'FieldExtraction');
    }

    // Clean up used dates for this document
    _usedDatesPerDocument.remove(documentId);

    return results;
  }

  Map<String, dynamic> _extractDateField(
      ExtractedTextData data, ExtractedDataModel field, String documentId) {
    final allKeys = [field.key, ...(field.alternativeKeys ?? [])];
    final usedDates = _usedDatesPerDocument[documentId] ?? {};

    // Try to find date associated with the field
    for (final key in allKeys) {
      final result = _findFieldValue(data, key, isDate: true);
      if (result['value'] != null) {
        final dateValue = result['value'] as String;

        // Validate and format the date with the reading format hint
        final formattedDate = _validateAndFormatDate(
            dateValue, field.dateFormat,
            readingFormat: field.dateReadingFormat);

        if (formattedDate != null && !usedDates.contains(formattedDate)) {
          usedDates.add(formattedDate);
          _usedDatesPerDocument[documentId] = usedDates;
          return {
            'value': formattedDate,
            'confidence': result['confidence'],
          };
        }
      }
    }

    // Fallback: Extract all dates and use contextual logic
    final allDatesInText = _extractAllDatesWithPosition(data);

    if (allDatesInText.isNotEmpty) {
      final lowerKey = field.key.toLowerCase();

      // Filter out already used dates
      final availableDates = allDatesInText.where((dateInfo) {
        final formatted = _validateAndFormatDate(
            dateInfo['date'], field.dateFormat,
            readingFormat: field.dateReadingFormat);
        return formatted != null && !usedDates.contains(formatted);
      }).toList();

      if (availableDates.isNotEmpty) {
        // Find the best date based on proximity to the field label
        Map<String, dynamic>? bestDateInfo;

        for (final key in allKeys) {
          final keyPosition = _findKeyPosition(data, key);
          if (keyPosition != null) {
            // Find the closest date after this key
            for (final dateInfo in availableDates) {
              if (dateInfo['position'] > keyPosition['endPosition']) {
                if (bestDateInfo == null ||
                    (dateInfo['position'] - keyPosition['endPosition']) <
                        (bestDateInfo['position'] -
                            keyPosition['endPosition'])) {
                  bestDateInfo = dateInfo;
                }
              }
            }
          }
        }
        final sortedDates =
            _sortDateInfoList(availableDates, field.dateReadingFormat);
        // If no date found after the key, use contextual logic
        if (bestDateInfo == null) {
          if (lowerKey.contains('expiry') ||
              lowerKey.contains('expire') ||
              lowerKey.contains('valid') ||
              lowerKey.contains('end')) {
            bestDateInfo = sortedDates.last; // Latest date for expiry
          } else if (lowerKey.contains('birth') ||
              lowerKey.contains('issue') ||
              lowerKey.contains('first') ||
              lowerKey.contains('start')) {
            bestDateInfo = sortedDates.first; // Earliest date for birth/issue
          } else {
            bestDateInfo = sortedDates.first; // Default to earliest
          }
        }

        if (bestDateInfo.isNotEmpty) {
          final formattedDate = _validateAndFormatDate(
              bestDateInfo['date'], field.dateFormat,
              readingFormat: field.dateReadingFormat);
          if (formattedDate != null) {
            usedDates.add(formattedDate);
            _usedDatesPerDocument[documentId] = usedDates;
            return {
              'value': formattedDate,
              'confidence': bestDateInfo == sortedDates.first ? 0.6 : 0.7,
            };
          }
        }
      }
    }

    return {'value': null, 'confidence': 0.0};
  }

  List<Map<String, dynamic>> _extractAllDatesWithPosition(
      ExtractedTextData data) {
    final datePatterns = [
      RegExp(r'\b\d{1,2}[/\-]\d{1,2}[/\-]\d{2,4}\b'),
      RegExp(r'\b\d{4}[/\-]\d{1,2}[/\-]\d{1,2}\b'),
      RegExp(
          r'\b\d{1,2}\s+(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+\d{4}\b',
          caseSensitive: false),
    ];

    final datesWithPosition = <Map<String, dynamic>>[];

    for (final pattern in datePatterns) {
      final matches = pattern.allMatches(data.fullText);
      for (final match in matches) {
        if (match.group(0) != null) {
          datesWithPosition.add({
            'date': match.group(0)!,
            'position': match.start,
          });
        }
      }
    }

    // Sort by position
    datesWithPosition.sort((a, b) => a['position'].compareTo(b['position']));

    return datesWithPosition;
  }

  Map<String, dynamic>? _findKeyPosition(ExtractedTextData data, String key) {
    final lowerKey = key.toLowerCase();
    final lowerText = data.fullText.toLowerCase();

    final index = lowerText.indexOf(lowerKey);
    if (index != -1) {
      return {
        'startPosition': index,
        'endPosition': index + key.length,
      };
    }

    return null;
  }

  List<Map<String, dynamic>> _sortDateInfoList(
      List<Map<String, dynamic>> dateInfoList, String? readingFormat) {
    final tempList = <Map<String, dynamic>>[];

    for (final dateInfo in dateInfoList) {
      final dateStr = dateInfo['date'] as String;
      final parsedDate = _parseDateString(dateStr, readingFormat);
      if (parsedDate != null) {
        tempList.add({
          ...dateInfo,
          'parsedDate': parsedDate,
        });
      }
    }

    tempList.sort((a, b) =>
        (a['parsedDate'] as DateTime).compareTo(b['parsedDate'] as DateTime));

    return tempList;
  }

  DateTime? _parseDateString(String dateStr, String? preferredFormat) {
    final formats = <DateFormat>[];

    // Add preferred format first if provided
    if (preferredFormat != null) {
      try {
        formats.add(DateFormat(preferredFormat));
      } catch (e) {
        dev.log('Invalid date format: $preferredFormat', name: 'DateParsing');
      }
    }

    // Add common formats
    formats.addAll([
      DateFormat("dd/MM/yyyy"),
      DateFormat("dd-MM-yyyy"),
      DateFormat("yyyy/MM/dd"),
      DateFormat("yyyy-MM-dd"),
      DateFormat("d/M/yyyy"),
      DateFormat("dd MMM yyyy"),
      DateFormat("MMM dd, yyyy"),
    ]);

    for (final format in formats) {
      try {
        return format.parse(dateStr);
      } catch (_) {
        // Try next format
      }
    }

    return null;
  }

  String? _validateAndFormatDate(String? dateStr, String? expectedFormat,
      {String? readingFormat}) {
    if (dateStr == null || dateStr.isEmpty) return null;

    final parsedDate = _parseDateString(dateStr, readingFormat);

    if (parsedDate != null) {
      // Validate the date is reasonable (not too far in past or future)
      final now = DateTime.now();
      final minDate = DateTime(1900);
      final maxDate = DateTime(now.year + 50);

      if (parsedDate.isBefore(minDate) || parsedDate.isAfter(maxDate)) {
        dev.log('Date out of reasonable range: $dateStr -> $parsedDate',
            name: 'DateValidation');
        return null;
      }

      final outputFormat = expectedFormat != null
          ? DateFormat(expectedFormat)
          : DateFormat("dd/MM/yyyy");
      return outputFormat.format(parsedDate);
    }

    return null;
  }

  Map<String, dynamic> _extractNumberField(
      ExtractedTextData data, ExtractedDataModel field) {
    final allKeys = [field.key, ...(field.alternativeKeys ?? [])];

    for (final key in allKeys) {
      final result = _findFieldValue(data, key, isNumber: true);
      if (result['value'] != null) {
        final numberValue = result['value'] as String;

        // Validate number/ID format
        if (_isValidNumber(numberValue, field.minLength, field.maxLength)) {
          return {
            'value': numberValue.trim(),
            'confidence': result['confidence'],
          };
        }
      }
    }

    // Fallback: look for numbers that match the criteria
    final numbers = data.extractNumbers();
    for (final number in numbers) {
      if (_isValidNumber(number, field.minLength, field.maxLength)) {
        return {
          'value': number.trim(),
          'confidence': 0.5, // Lower confidence for fallback
        };
      }
    }

    return {'value': null, 'confidence': 0.0};
  }

  Map<String, dynamic> _extractStringField(
      ExtractedTextData data, ExtractedDataModel field) {
    final allKeys = [field.key, ...(field.alternativeKeys ?? [])];

    for (final key in allKeys) {
      final result = _findFieldValue(data, key, isString: true);
      if (result['value'] != null) {
        final stringValue = result['value'] as String;

        // Clean and validate string value
        final cleanedValue = _cleanStringValue(stringValue, field.key);
        if (cleanedValue != null &&
            _isValidStringValue(cleanedValue, field.key)) {
          return {
            'value': cleanedValue,
            'confidence': result['confidence'],
          };
        }
      }
    }

    // For name fields, try to find proper names
    if (field.key.toLowerCase().contains('name')) {
      final potentialNames = data.textLines
          .where((line) => _isPotentialName(line))
          .map((line) => _cleanStringValue(line, field.key))
          .where((name) => name != null && name.isNotEmpty)
          .toList();

      if (potentialNames.isNotEmpty) {
        return {
          'value': potentialNames.first,
          'confidence': 0.7,
        };
      }
    }

    return {'value': null, 'confidence': 0.0};
  }

  Map<String, dynamic> _findFieldValue(ExtractedTextData data, String key,
      {bool isDate = false, bool isNumber = false, bool isString = false}) {
    final lines = data.textLines;
    final lowerKey = key.toLowerCase();

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final lowerLine = line.toLowerCase();

      // Check if this line contains the field key
      if (_lineContainsKey(lowerLine, lowerKey)) {
        double confidence = 0.8; // High confidence for direct match

        // First check same line after colon or dash
        final colonMatch = RegExp(
          '${_createFlexiblePattern(key)}\\s*[:\\-]\\s*(.+)',
          caseSensitive: false,
        ).firstMatch(line);

        if (colonMatch != null && colonMatch.group(1) != null) {
          final value = colonMatch.group(1)!.trim();
          if (_isAppropriateValueType(value,
              isDate: isDate, isNumber: isNumber, isString: isString)) {
            return {'value': value, 'confidence': confidence};
          }
        }

        // Check next lines
        for (int j = 1; j <= 3 && i + j < lines.length; j++) {
          final nextLine = lines[i + j].trim();

          if (nextLine.isNotEmpty &&
              !_isCommonKeyword(nextLine) &&
              !nextLine.toLowerCase().contains(':') &&
              _isAppropriateValueType(nextLine,
                  isDate: isDate, isNumber: isNumber, isString: isString)) {
            // Reduce confidence for values found on subsequent lines
            confidence -= (j * 0.1);
            return {'value': nextLine, 'confidence': confidence};
          }
        }
      }
    }

    return {'value': null, 'confidence': 0.0};
  }

  bool _isAppropriateValueType(String value,
      {bool isDate = false, bool isNumber = false, bool isString = false}) {
    if (isDate) {
      return TextProcessingUtils.isValidDate(value) ||
          RegExp(r'\d{4}/\d{2}/\d{2}').hasMatch(value);
    } else if (isNumber) {
      return RegExp(r'^\d+[A-Z0-9]*$').hasMatch(value) && value.length >= 4;
    } else if (isString) {
      return value.length >= 2 && !RegExp(r'^\d+$').hasMatch(value);
    }
    return true;
  }

  bool _isValidNumber(String value, int? minLength, int? maxLength) {
    if (value.isEmpty) return false;

    // Check length constraints
    if (minLength != null && value.length < minLength) return false;
    if (maxLength != null && value.length > maxLength) return false;

    // Must start with digit
    if (!RegExp(r'^\d').hasMatch(value)) return false;

    // Must be primarily numeric
    final digitCount = value.replaceAll(RegExp(r'[^\d]'), '').length;
    if (digitCount < value.length * 0.7) return false;

    return !_isCommonKeyword(value);
  }

  String? _cleanStringValue(String? value, String fieldKey) {
    if (value == null || value.isEmpty) return null;

    String cleaned = value.trim();

    // Remove field labels from the beginning
    final possibleLabels = [
      fieldKey,
      fieldKey.replaceAll(' ', ''),
      ...fieldKey.split(' '),
    ];

    for (final label in possibleLabels) {
      final pattern = RegExp('^${RegExp.escape(label)}\\s*[:\\-]?\\s*',
          caseSensitive: false);
      cleaned = cleaned.replaceFirst(pattern, '');
    }

    // Clean up extra spaces
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();

    return cleaned.isNotEmpty ? cleaned : null;
  }

  String _createFlexiblePattern(String fieldKey) {
    final words = fieldKey.split(' ');
    final flexibleWords = words.map((word) {
      if (word.toLowerCase() == 'license') {
        return '(?:license|licence)';
      } else if (word.toLowerCase() == 'number') {
        return '(?:number|no\\.?|num\\.?|#)';
      } else if (word.toLowerCase() == 'date') {
        return '(?:date|dt)';
      }
      return RegExp.escape(word);
    }).toList();

    return flexibleWords.join('\\s*');
  }

  bool _lineContainsKey(String line, String key) {
    final keyWords = key.split(' ').where((w) => w.isNotEmpty).toList();
    return keyWords.every((word) => line.contains(word.toLowerCase()));
  }

  bool _isValidStringValue(String value, String fieldKey) {
    if (value.isEmpty || value.length < 2) return false;

    // Filter out MRZ patterns
    if (value.contains('<') || value.contains('>')) return false;

    // Filter out values that look like IDs or codes
    if (RegExp(r'^[A-Z]{2,5}\d{6,}').hasMatch(value)) return false;

    // Filter out values that are mostly numbers
    final digitCount = value.replaceAll(RegExp(r'[^\d]'), '').length;
    if (digitCount > value.length * 0.5) return false;

    // Filter out common keywords
    if (_isCommonKeyword(value)) return false;

    // Field-specific validation
    final lowerKey = fieldKey.toLowerCase();
    if (lowerKey.contains('nationality')) {
      if (value.split(' ').length > 3) return false;
      if (!RegExp(r'^[A-Z\s]+$', caseSensitive: false).hasMatch(value))
        return false;
    }

    if (lowerKey.contains('name')) {
      final parts = value.split(' ').where((p) => p.isNotEmpty).toList();
      if (parts.length < 2) return false;
      if (parts.any((p) => p.length < 2)) return false;
    }

    return true;
  }

  bool _isPotentialName(String line) {
    final trimmed = line.trim();

    if (trimmed.isEmpty || trimmed.length < 5 || trimmed.length > 50)
      return false;
    if (trimmed.contains('<') || trimmed.contains('>')) return false;

    final digitCount = trimmed.replaceAll(RegExp(r'[^\d]'), '').length;
    if (digitCount > trimmed.length * 0.3) return false;

    if (trimmed != trimmed.toUpperCase()) return false;

    final words = trimmed.split(' ').where((w) => w.length >= 2).toList();
    if (words.length < 2) return false;

    final documentKeywords = [
      'sultanate',
      'oman',
      'police',
      'licence',
      'license',
      'card',
      'resident',
      'driving',
      'vehicle',
      'authority',
      'directorate',
      'general',
      'traffic',
      'civil',
      'number',
      'expiry',
      'date',
      'issue',
      'first',
      'blood',
      'group',
      'class',
      'note',
      'royal'
    ];

    final lowerLine = trimmed.toLowerCase();
    for (final keyword in documentKeywords) {
      if (lowerLine.contains(keyword)) return false;
    }

    return true;
  }

  bool _isCommonKeyword(String text) {
    final commonKeywords = [
      'oman',
      'police',
      'sultanate',
      'authority',
      'directorate',
      'general',
      'traffic',
      'vehicle',
      'driving',
      'licence',
      'license',
      'royal',
      'issue',
      'at',
      'first',
      'issued',
      'expiry',
      'date',
      'name',
      'nationality',
      'civil',
      'id',
      'card',
      'number',
      'registration'
    ];

    final lowerText = text.toLowerCase();
    return commonKeywords.any((keyword) => lowerText.contains(keyword));
  }

  void dispose() {
    _textRecognizer?.close();
    _textRecognizer = null;
    _usedDatesPerDocument.clear();
  }
}

// Rest of the classes remain the same...
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
      RegExp(r'\b\d{4}[/\-]\d{1,2}[/\-]\d{1,2}\b'),
      RegExp(
          r'\b\d{1,2}\s+(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+\d{4}\b',
          caseSensitive: false),
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
    final patterns = [
      RegExp(r'\b\d{6,}\b'),
      RegExp(r'\b\d{5,}[A-Z0-9]*\b'),
      RegExp(r'\b[A-Z]?\d{6,}\b'),
    ];

    final numbers = <String>{};
    for (final pattern in patterns) {
      final matches = pattern.allMatches(fullText);
      for (final match in matches) {
        if (match.group(0) != null) {
          final number = match.group(0)!;
          if (!number.contains('/') && !number.contains('-')) {
            numbers.add(number);
          }
        }
      }
    }

    return numbers.toList();
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
      DateFormat("yyyy/MM/dd"),
      DateFormat("yyyy-MM-dd"),
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
      RegExp(r'^\d{4}/\d{2}/\d{2}$'),
      RegExp(r'^\d{4}-\d{2}-\d{2}$'),
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

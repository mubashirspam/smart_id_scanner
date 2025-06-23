import 'dart:developer' as dev;
import 'dart:io';
import 'text_extraction_service.dart';

class DocumentScannerService {
  final TextExtractionService _textExtractor;
  
  DocumentScannerService(this._textExtractor);
  
  Future<DocumentScanResult?> scanDocument({
    required File imageFile,
    required List<String> validationKeywords,
    required List<ExtractedDataModel> fieldsToExtract,
  }) async {
    try {
      dev.log('Starting document scan', name: 'DocumentScanner');
      
      // Step 1: Validate document type
      final isValidDocument = await _textExtractor.validateDocumentType(
        imageFile, 
        validationKeywords,
      );
      
      if (!isValidDocument) {
        dev.log('Document validation failed', name: 'DocumentScanner');
        return DocumentScanResult(
          isValid: false,
          extractedFields: [],
          errorMessage: 'Document does not match expected type',
        );
      }
      
      // Step 2: Extract specific fields
      final extractedFields = await _textExtractor.extractSpecificFields(
        imageFile,
        fieldsToExtract,
      );
      
      dev.log('Successfully extracted ${extractedFields.length} fields', 
          name: 'DocumentScanner');
      
      return DocumentScanResult(
        isValid: true,
        extractedFields: extractedFields,
      );
      
    } catch (e) {
      dev.log('Error scanning document: $e', name: 'DocumentScanner');
      return DocumentScanResult(
        isValid: false,
        extractedFields: [],
        errorMessage: 'Error scanning document: $e',
      );
    }
  }
  
  void dispose() {
    _textExtractor.dispose();
  }
}

class DocumentScanResult {
  final bool isValid;
  final List<ExtractedFieldResult> extractedFields;
  final String? errorMessage;
  
  DocumentScanResult({
    required this.isValid,
    required this.extractedFields,
    this.errorMessage,
  });
  
  Map<String, dynamic> toMap() {
    final result = <String, dynamic>{
      'isValid': isValid,
      'errorMessage': errorMessage,
    };
    
    for (final field in extractedFields) {
      result[field.key] = field.value;
    }
    
    return result;
  }
}
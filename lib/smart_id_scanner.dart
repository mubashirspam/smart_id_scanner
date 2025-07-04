library smart_id_scanner;

// Export main widgets
export 'src/views/smart_id_scanner_widget.dart';
export 'src/views/permission_handler_widget.dart';

// Export controller
export 'src/controller/document_scanning_controller.dart';

// Export services if needed by consumers
export 'src/services/text_extraction_service.dart' show ExtractedDataModel, ExtractedDataType, ExtractedFieldResult;

// Don't export internal services unless needed
// export 'src/services/document_scanner_service.dart';
// export 'src/services/camera_controller_service.dart';`
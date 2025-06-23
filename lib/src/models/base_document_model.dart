// lib/models/base_document_model.dart

abstract class BaseDocumentModel {
  Map<String, dynamic> toJson();
  String getDisplayName();
  List<DocumentField> getFields();
  
  @override
  String toString() {
    final fields = getFields();
    final buffer = StringBuffer();
    
    for (final field in fields) {
      if (field.value != null && field.value!.isNotEmpty) {
        buffer.writeln('${field.label} = ${field.value}');
      }
    }
    
    return buffer.toString();
  }
}

class DocumentField {
  final String key;
  final String label;
  final String? value;
  final bool isRequired;
  final DocumentFieldType type;

  DocumentField({
    required this.key,
    required this.label,
    this.value,
    this.isRequired = false,
    this.type = DocumentFieldType.text,
  });
}

enum DocumentFieldType {
  text,
  date,
  number,
  image,
}

// Specific implementation for Civil ID
class CivilIdModel extends BaseDocumentModel {
  final String name;
  final String civilNumber;
  final String? expiryDate;
  final String? dateOfBirth;
  final String? nationality;
  final String? profession;
  final String? placeOfBirth;
  final String? drivingLicenseClass;
  final String? idNumber;

  CivilIdModel({
    required this.name,
    required this.civilNumber,
    this.expiryDate,
    this.dateOfBirth,
    this.nationality,
    this.profession,
    this.placeOfBirth,
    this.drivingLicenseClass,
    this.idNumber,
  });

  @override
  String getDisplayName() => 'Civil ID Card';

  @override
  List<DocumentField> getFields() => [
    DocumentField(
      key: 'name',
      label: 'Name',
      value: name,
      isRequired: true,
    ),
    DocumentField(
      key: 'civilNumber',
      label: 'Civil Number',
      value: civilNumber,
      isRequired: true,
      type: DocumentFieldType.number,
    ),
    DocumentField(
      key: 'nationality',
      label: 'Nationality',
      value: nationality,
    ),
    DocumentField(
      key: 'dateOfBirth',
      label: 'Date of Birth',
      value: dateOfBirth,
      type: DocumentFieldType.date,
    ),
    DocumentField(
      key: 'expiryDate',
      label: 'Expiry Date',
      value: expiryDate,
      type: DocumentFieldType.date,
    ),
    DocumentField(
      key: 'profession',
      label: 'Profession',
      value: profession,
    ),
    DocumentField(
      key: 'placeOfBirth',
      label: 'Place of Birth',
      value: placeOfBirth,
    ),
  ];

  @override
  Map<String, dynamic> toJson() => {
    'name': name,
    'civilNumber': civilNumber,
    'nationality': nationality,
    'dateOfBirth': dateOfBirth,
    'expiryDate': expiryDate,
    'profession': profession,
    'placeOfBirth': placeOfBirth,
    'drivingLicenseClass': drivingLicenseClass,
    'idNumber': idNumber,
  };

  factory CivilIdModel.fromOcrData(Map<String, String> data) {
    return CivilIdModel(
      name: data['name'] ?? '',
      civilNumber: data['civil_number'] ?? '',
      expiryDate: data['expiry_date'],
      dateOfBirth: data['date_of_birth'],
      nationality: data['nationality'],
      profession: data['profession'],
      placeOfBirth: data['place_of_birth'],
      drivingLicenseClass: data['license_class'],
      idNumber: data['id_number'],
    );
  }
}

// Example: Driving License Model
class DrivingLicenseModel extends BaseDocumentModel {
  final String name;
  final String licenseNumber;
  final String? expiryDate;
  final String? issueDate;
  final String? dateOfBirth;
  final String? nationality;
  final String? licenseClass;
  final String? restrictions;

  DrivingLicenseModel({
    required this.name,
    required this.licenseNumber,
    this.expiryDate,
    this.issueDate,
    this.dateOfBirth,
    this.nationality,
    this.licenseClass,
    this.restrictions,
  });

  @override
  String getDisplayName() => 'Driving License';

  @override
  List<DocumentField> getFields() => [
    DocumentField(
      key: 'name',
      label: 'Name',
      value: name,
      isRequired: true,
    ),
    DocumentField(
      key: 'licenseNumber',
      label: 'License Number',
      value: licenseNumber,
      isRequired: true,
      type: DocumentFieldType.number,
    ),
    DocumentField(
      key: 'licenseClass',
      label: 'License Class',
      value: licenseClass,
    ),
    DocumentField(
      key: 'dateOfBirth',
      label: 'Date of Birth',
      value: dateOfBirth,
      type: DocumentFieldType.date,
    ),
    DocumentField(
      key: 'issueDate',
      label: 'Issue Date',
      value: issueDate,
      type: DocumentFieldType.date,
    ),
    DocumentField(
      key: 'expiryDate',
      label: 'Expiry Date',
      value: expiryDate,
      type: DocumentFieldType.date,
    ),
    DocumentField(
      key: 'nationality',
      label: 'Nationality',
      value: nationality,
    ),
    DocumentField(
      key: 'restrictions',
      label: 'Restrictions',
      value: restrictions,
    ),
  ];

  @override
  Map<String, dynamic> toJson() => {
    'name': name,
    'licenseNumber': licenseNumber,
    'nationality': nationality,
    'dateOfBirth': dateOfBirth,
    'issueDate': issueDate,
    'expiryDate': expiryDate,
    'licenseClass': licenseClass,
    'restrictions': restrictions,
  };
}
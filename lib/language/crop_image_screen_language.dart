class CropImageScreenLanguage {
  static Map<String, Map<String, String>> translations = {
    'en': {
      'crop': 'Crop',
      'done': 'Done',
    },
    'hi': {
      'crop': 'क्रॉप करें',
      'done': 'हो गया',
    },
    'es': {
      'crop': 'Recortar',
      'done': 'Listo',
    },
    'ps': {
      'crop': 'کcrop کړئ',
      'done': 'شوی',
    },
    'fil': {
      'crop': 'I-crop',
      'done': 'Tapos na',
    },
    'id': {
      'crop': 'Potong',
      'done': 'Selesai',
    },
    'my': {
      'crop': 'ဖြတ်ရန်',
      'done': 'ပြီးပါပြီ',
    },
    'ru': {
      'crop': 'Обрезать',
      'done': 'Готово',
    },
    'fa': {
      'crop': 'برش',
      'done': 'انجام شد',
    },
    'bn': {
      'crop': 'ক্রপ করুন',
      'done': 'সম্পন্ন',
    },
    'mr': {
      'crop': 'क्रॉप करा',
      'done': 'झाले',
    },
    'te': {
      'crop': 'క్రాప్ చేయండి',
      'done': 'పూర్తయింది',
    },
    'ta': {
      'crop': 'செதுக்கு',
      'done': 'முடிந்தது',
    },
    'ur': {
      'crop': 'کراپ کریں',
      'done': 'ہو گیا',
    },
    'ms': {
      'crop': 'Potong',
      'done': 'Selesai',
    },
    'pt': {
      'crop': 'Recortar',
      'done': 'Concluído',
    },
    'fr': {
      'crop': 'Recadrer',
      'done': 'Terminé',
    },
    'de': {
      'crop': 'Zuschneiden',
      'done': 'Fertig',
    },
    'ar': {
      'crop': 'قص',
      'done': 'تم',
    },
    'tr': {
      'crop': 'Kırp',
      'done': 'Bitti',
    },
    'vi': {
      'crop': 'Cắt',
      'done': 'Xong',
    },
    'th': {
      'crop': 'ครอบตัด',
      'done': 'เสร็จสิ้น',
    },
    'ja': {
      'crop': '切り抜き',
      'done': '完了',
    },
    'ko': {
      'crop': '자르기',
      'done': '완료',
    },
    'it': {
      'crop': 'Ritaglia',
      'done': 'Fatto',
    },
    'pl': {
      'crop': 'Przytnij',
      'done': 'Gotowe',
    },
    'uk': {
      'crop': 'Обрізати',
      'done': 'Готово',
    },
    'nl': {
      'crop': 'Bijsnijden',
      'done': 'Klaar',
    },
    'ro': {
      'crop': 'Decupați',
      'done': 'Gata',
    },
    'el': {
      'crop': 'Περικοπή',
      'done': 'Τέλος',
    },
    'cs': {
      'crop': 'Oříznout',
      'done': 'Hotovo',
    },
    'hu': {
      'crop': 'Kivágás',
      'done': 'Kész',
    },
    'sv': {
      'crop': 'Beskär',
      'done': 'Klar',
    },
    'zh': {
      'crop': '裁剪',
      'done': '完成',
    },
    'he': {
      'crop': 'גזור',
      'done': 'בוצע',
    },
    'da': {
      'crop': 'Beskær',
      'done': 'Færdig',
    },
    'fi': {
      'crop': 'Rajaa',
      'done': 'Valmis',
    },
    'no': {
      'crop': 'Beskjær',
      'done': 'Ferdig',
    },
    'sk': {
      'crop': 'Orezať',
      'done': 'Hotovo',
    },
    'bg': {
      'crop': 'Изрязване',
      'done': 'Готово',
    },
    'hr': {
      'crop': 'Obreži',
      'done': 'Gotovo',
    },
    'sr': {
      'crop': 'Обрежи',
      'done': 'Готово',
    },
    'ca': {
      'crop': 'Retallar',
      'done': 'Fet',
    },
  };

  static String getCrop(String languageCode) => getText(languageCode, 'crop');
  static String getDone(String languageCode) => getText(languageCode, 'done');

  static String getText(String languageCode, String key) {
    return translations[languageCode]?[key] ?? translations['en']![key]!;
  }
}

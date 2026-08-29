/// ISO 3166-1 alpha-2 to numeric country codes.
///
/// Two parts of the app speak numeric ids rather than letters: the world-atlas
/// geometry the map is drawn from keys its countries by them, and the voting
/// backend answers with them (`{"won": ["784"]}`, see docs/voting-api.md).
/// Everything else in the app carries the alpha-2 code, so the translation
/// lives here once instead of in each of them.
///
/// The table covers the countries the location parser recognizes plus the ones
/// the map can be voted on; a code that is not listed simply has no numeric
/// counterpart, which reads as "no match" everywhere it is used.
const Map<String, String> ccIso = {
  'AE': '784', 'AL': '008', 'AM': '051', 'AR': '032', 'AT': '040',
  'AU': '036', 'AZ': '031', 'BA': '070', 'BE': '056', 'BG': '100',
  'BR': '076', 'BY': '112', 'CA': '124', 'CH': '756', 'CL': '152',
  'CO': '170', 'CY': '196', 'CZ': '203', 'DE': '276', 'DK': '208',
  'EE': '233', 'EG': '818', 'ES': '724', 'FI': '246', 'FR': '250',
  'GB': '826', 'GE': '268', 'GR': '300', 'HK': '344', 'HR': '191',
  'HU': '348', 'ID': '360', 'IE': '372', 'IL': '376', 'IN': '356',
  'IS': '352', 'IT': '380', 'JP': '392', 'KR': '410', 'KZ': '398',
  'LT': '440', 'LU': '442', 'LV': '428', 'MD': '498', 'ME': '499',
  'MK': '807', 'MT': '470', 'MX': '484', 'MY': '458', 'NL': '528',
  'NO': '578', 'NZ': '554', 'PH': '608', 'PL': '616', 'PT': '620',
  'RO': '642', 'RS': '688', 'RU': '643', 'SA': '682', 'SE': '752',
  'SG': '702', 'SI': '705', 'SK': '703', 'TH': '764', 'TR': '792',
  'TW': '158', 'UA': '804', 'US': '840', 'VN': '704', 'ZA': '710',
};

/// The numeric id for [cc], or null when there is no entry for it. Case is
/// not significant: locations carry the code upper case, links do not always.
String? ccNumeric(String cc) => ccIso[cc.toUpperCase()];
